#define _GNU_SOURCE

#include "clipboard_internal.h"

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <wayland-client.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>

static int64_t mono_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

/* ---------- Wayland ---------- */

#define PPUX_WL_MAX_OFFERS 16

typedef struct PpuxWlOffer {
  struct wl_data_offer *offer;
  int has_png;
  int has_bmp;
  int live;
} PpuxWlOffer;

typedef struct PpuxWlState {
  struct wl_seat *seat;
  struct wl_data_device_manager *manager;
  struct wl_data_device *device;
  PpuxWlOffer offers[PPUX_WL_MAX_OFFERS];
  int offer_count;
  struct wl_data_offer *selection;
} PpuxWlState;

static PpuxWlOffer *wl_offer_slot(PpuxWlState *st, struct wl_data_offer *offer) {
  for (int i = 0; i < st->offer_count; i++) {
    if (st->offers[i].live && st->offers[i].offer == offer) {
      return &st->offers[i];
    }
  }
  return NULL;
}

static void wl_offer_offer(void *data, struct wl_data_offer *offer, const char *mime) {
  PpuxWlState *st = data;
  PpuxWlOffer *slot = wl_offer_slot(st, offer);
  if (!slot || !mime) {
    return;
  }
  if (strcmp(mime, "image/png") == 0) {
    slot->has_png = 1;
  } else if (strcmp(mime, "image/bmp") == 0) {
    slot->has_bmp = 1;
  }
}

static const struct wl_data_offer_listener wl_offer_listener = {
  .offer = wl_offer_offer,
};

static void wl_device_data_offer(void *data, struct wl_data_device *device, struct wl_data_offer *id) {
  (void)device;
  PpuxWlState *st = data;
  if (st->offer_count >= PPUX_WL_MAX_OFFERS) {
    wl_data_offer_destroy(id);
    return;
  }
  PpuxWlOffer *slot = &st->offers[st->offer_count++];
  slot->offer = id;
  slot->has_png = 0;
  slot->has_bmp = 0;
  slot->live = 1;
  wl_data_offer_add_listener(id, &wl_offer_listener, st);
}

static void wl_device_enter(
  void *data,
  struct wl_data_device *device,
  uint32_t serial,
  struct wl_surface *surface,
  wl_fixed_t x,
  wl_fixed_t y,
  struct wl_data_offer *id
) {
  (void)data; (void)device; (void)serial; (void)surface; (void)x; (void)y; (void)id;
}

static void wl_device_leave(void *data, struct wl_data_device *device) {
  (void)data; (void)device;
}

static void wl_device_motion(
  void *data,
  struct wl_data_device *device,
  uint32_t time,
  wl_fixed_t x,
  wl_fixed_t y
) {
  (void)data; (void)device; (void)time; (void)x; (void)y;
}

static void wl_device_drop(void *data, struct wl_data_device *device) {
  (void)data; (void)device;
}

static void wl_device_selection(void *data, struct wl_data_device *device, struct wl_data_offer *id) {
  (void)device;
  PpuxWlState *st = data;
  st->selection = id;
}

static const struct wl_data_device_listener wl_device_listener = {
  .data_offer = wl_device_data_offer,
  .enter = wl_device_enter,
  .leave = wl_device_leave,
  .motion = wl_device_motion,
  .drop = wl_device_drop,
  .selection = wl_device_selection,
};

static void wl_seat_capabilities(void *data, struct wl_seat *seat, uint32_t caps) {
  (void)data; (void)seat; (void)caps;
}

static void wl_seat_name(void *data, struct wl_seat *seat, const char *name) {
  (void)data; (void)seat; (void)name;
}

static const struct wl_seat_listener wl_seat_listener = {
  .capabilities = wl_seat_capabilities,
  .name = wl_seat_name,
};

static void wl_registry_global(
  void *data,
  struct wl_registry *registry,
  uint32_t name,
  const char *interface,
  uint32_t version
) {
  PpuxWlState *st = data;
  if (!interface) {
    return;
  }
  if (!st->seat && strcmp(interface, wl_seat_interface.name) == 0) {
    uint32_t ver = version < 2 ? version : 2;
    if (ver < 1) {
      ver = 1;
    }
    st->seat = wl_registry_bind(registry, name, &wl_seat_interface, ver);
    wl_seat_add_listener(st->seat, &wl_seat_listener, st);
  } else if (!st->manager && strcmp(interface, wl_data_device_manager_interface.name) == 0) {
    st->manager = wl_registry_bind(registry, name, &wl_data_device_manager_interface, 1);
  }
}

static void wl_registry_global_remove(void *data, struct wl_registry *registry, uint32_t name) {
  (void)data; (void)registry; (void)name;
}

static const struct wl_registry_listener wl_registry_listener = {
  .global = wl_registry_global,
  .global_remove = wl_registry_global_remove,
};

static int read_pipe_with_display(struct wl_display *dpy, int fd, uint8_t **out, size_t *out_len) {
  const size_t max_bytes = 32u * 1024u * 1024u;
  size_t cap = 8192;
  size_t len = 0;
  uint8_t *buf = (uint8_t *)malloc(cap);
  if (!buf) {
    ppux_clipboard_set_error("out of memory");
    return -1;
  }
  int dpy_fd = wl_display_get_fd(dpy);
  int64_t deadline = mono_ms() + 2000;
  for (;;) {
    if (mono_ms() >= deadline) {
      free(buf);
      ppux_clipboard_set_error("timed out reading Wayland clipboard");
      return -1;
    }
    while (wl_display_prepare_read(dpy) != 0) {
      if (wl_display_dispatch_pending(dpy) < 0) {
        free(buf);
        ppux_clipboard_set_error("Wayland dispatch failed");
        return -1;
      }
    }
    if (wl_display_flush(dpy) < 0 && errno != EAGAIN) {
      wl_display_cancel_read(dpy);
      free(buf);
      ppux_clipboard_set_error("Wayland flush failed");
      return -1;
    }
    struct pollfd pf[2];
    pf[0].fd = dpy_fd;
    pf[0].events = POLLIN;
    pf[0].revents = 0;
    pf[1].fd = fd;
    pf[1].events = POLLIN;
    pf[1].revents = 0;
    int wait_ms = (int)(deadline - mono_ms());
    if (wait_ms < 0) {
      wait_ms = 0;
    }
    int pr = poll(pf, 2, wait_ms);
    if (pr < 0 && errno == EINTR) {
      wl_display_cancel_read(dpy);
      continue;
    }
    if (pr < 0) {
      wl_display_cancel_read(dpy);
      free(buf);
      ppux_clipboard_set_error("poll failed");
      return -1;
    }
    if (pf[0].revents & (POLLIN | POLLERR | POLLHUP)) {
      if (wl_display_read_events(dpy) < 0) {
        free(buf);
        ppux_clipboard_set_error("Wayland read failed");
        return -1;
      }
    } else {
      wl_display_cancel_read(dpy);
    }
    if (wl_display_dispatch_pending(dpy) < 0) {
      free(buf);
      ppux_clipboard_set_error("Wayland dispatch failed");
      return -1;
    }
    if (pf[1].revents & (POLLIN | POLLHUP | POLLERR)) {
      for (;;) {
        if (len >= max_bytes) {
          free(buf);
          ppux_clipboard_set_error("clipboard image is too large");
          return -1;
        }
        if (len == cap) {
          size_t next = cap * 2;
          if (next > max_bytes) {
            next = max_bytes;
          }
          uint8_t *grown = (uint8_t *)realloc(buf, next);
          if (!grown) {
            free(buf);
            ppux_clipboard_set_error("out of memory");
            return -1;
          }
          buf = grown;
          cap = next;
        }
        ssize_t n = read(fd, buf + len, cap - len);
        if (n > 0) {
          len += (size_t)n;
          continue;
        }
        if (n == 0) {
          *out = buf;
          *out_len = len;
          return 0;
        }
        if (errno == EINTR) {
          continue;
        }
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
          break;
        }
        free(buf);
        ppux_clipboard_set_error("failed to read clipboard pipe");
        return -1;
      }
    }
  }
}

static int wayland_get_image(
  uint8_t **out_bytes,
  size_t *out_size,
  int32_t *out_format
) {
  struct wl_display *dpy = wl_display_connect(NULL);
  if (!dpy) {
    ppux_clipboard_set_error("Wayland connect failed");
    return PPUX_CLIP_UNAVAILABLE;
  }
  int fds[2] = { -1, -1 };
  uint8_t *bytes = NULL;
  size_t size = 0;

  PpuxWlState st;
  memset(&st, 0, sizeof(st));
  struct wl_registry *registry = wl_display_get_registry(dpy);
  wl_registry_add_listener(registry, &wl_registry_listener, &st);
  if (wl_display_roundtrip(dpy) < 0) {
    wl_registry_destroy(registry);
    wl_display_disconnect(dpy);
    ppux_clipboard_set_error("Wayland roundtrip failed");
    return PPUX_CLIP_ERR;
  }
  if (!st.seat || !st.manager) {
    if (st.manager) {
      wl_data_device_manager_destroy(st.manager);
    }
    if (st.seat) {
      wl_seat_destroy(st.seat);
    }
    wl_registry_destroy(registry);
    wl_display_disconnect(dpy);
    ppux_clipboard_set_error("Wayland clipboard is unavailable");
    return PPUX_CLIP_UNAVAILABLE;
  }

  st.device = wl_data_device_manager_get_data_device(st.manager, st.seat);
  wl_data_device_add_listener(st.device, &wl_device_listener, &st);
  int rc = PPUX_CLIP_ERR;
  if (wl_display_roundtrip(dpy) < 0) {
    ppux_clipboard_set_error("Wayland selection roundtrip failed");
    goto cleanup;
  }

  PpuxWlOffer *selected = st.selection ? wl_offer_slot(&st, st.selection) : NULL;
  if (!selected || (!selected->has_png && !selected->has_bmp)) {
    ppux_clipboard_set_error("No image on the clipboard");
    rc = PPUX_CLIP_EMPTY;
    goto cleanup;
  }

  const char *mime = selected->has_png ? "image/png" : "image/bmp";
  int32_t format = selected->has_png ? PPUX_CLIP_FMT_PNG : PPUX_CLIP_FMT_BMP;
  if (pipe2(fds, O_CLOEXEC) != 0) {
    ppux_clipboard_set_error("pipe failed");
    goto cleanup;
  }
  int flags = fcntl(fds[0], F_GETFL, 0);
  if (flags >= 0) {
    fcntl(fds[0], F_SETFL, flags | O_NONBLOCK);
  }
  wl_data_offer_receive(selected->offer, mime, fds[1]);
  close(fds[1]);
  fds[1] = -1;

  if (read_pipe_with_display(dpy, fds[0], &bytes, &size) != 0) {
    goto cleanup;
  }
  close(fds[0]);
  fds[0] = -1;
  if (size == 0) {
    free(bytes);
    ppux_clipboard_set_error("clipboard image was empty");
    goto cleanup;
  }
  *out_bytes = bytes;
  *out_size = size;
  *out_format = format;
  rc = PPUX_CLIP_OK;

cleanup:
  if (fds[0] >= 0) {
    close(fds[0]);
  }
  if (fds[1] >= 0) {
    close(fds[1]);
  }
  for (int i = 0; i < st.offer_count; i++) {
    if (st.offers[i].live && st.offers[i].offer) {
      wl_data_offer_destroy(st.offers[i].offer);
    }
  }
  if (st.device) {
    wl_data_device_destroy(st.device);
  }
  if (st.manager) {
    wl_data_device_manager_destroy(st.manager);
  }
  if (st.seat) {
    wl_seat_destroy(st.seat);
  }
  wl_registry_destroy(registry);
  wl_display_disconnect(dpy);
  return rc;
}

/* ---------- X11 ---------- */

static int g_x_error;

static int x_error_handler(Display *dpy, XErrorEvent *ev) {
  (void)dpy;
  g_x_error = ev->error_code;
  return 0;
}

static int x11_wait(Display *dpy, int (*match)(const XEvent *, void *), void *ud, int timeout_ms, XEvent *out) {
  int fd = ConnectionNumber(dpy);
  int64_t deadline = mono_ms() + timeout_ms;
  for (;;) {
    while (XPending(dpy)) {
      XEvent ev;
      XNextEvent(dpy, &ev);
      if (match(&ev, ud)) {
        *out = ev;
        return 1;
      }
    }
    int64_t now = mono_ms();
    if (now >= deadline) {
      return 0;
    }
    struct pollfd pfd;
    pfd.fd = fd;
    pfd.events = POLLIN;
    pfd.revents = 0;
    int pr = poll(&pfd, 1, (int)(deadline - now));
    if (pr < 0 && errno == EINTR) {
      continue;
    }
    if (pr <= 0) {
      return 0;
    }
  }
}

typedef struct X11SelMatch {
  Window win;
  Atom selection;
} X11SelMatch;

typedef struct X11PropMatch {
  Window win;
  Atom prop;
} X11PropMatch;

static int match_selection(const XEvent *ev, void *ud) {
  const X11SelMatch *m = ud;
  return ev->type == SelectionNotify
    && ev->xselection.requestor == m->win
    && ev->xselection.selection == m->selection;
}

static int match_property(const XEvent *ev, void *ud) {
  const X11PropMatch *m = ud;
  return ev->type == PropertyNotify
    && ev->xproperty.window == m->win
    && ev->xproperty.atom == m->prop
    && ev->xproperty.state == PropertyNewValue;
}

static int append_bytes(uint8_t **buf, size_t *len, size_t *cap, const uint8_t *src, size_t n) {
  const size_t max_bytes = 32u * 1024u * 1024u;
  if (n > max_bytes || *len > max_bytes - n) {
    ppux_clipboard_set_error("clipboard image is too large");
    return -1;
  }
  if (*len + n > *cap) {
    size_t next = *cap ? *cap : 8192;
    while (next < *len + n) {
      next *= 2;
    }
    uint8_t *grown = (uint8_t *)realloc(*buf, next);
    if (!grown) {
      ppux_clipboard_set_error("out of memory");
      return -1;
    }
    *buf = grown;
    *cap = next;
  }
  if (n > 0) {
    memcpy(*buf + *len, src, n);
    *len += n;
  }
  return 0;
}

/* Read the current property value. Does not delete it.
 * *out_type is the property type. Caller XFree's nothing; bytes are copied.
 */
static int x11_copy_property(
  Display *dpy,
  Window win,
  Atom prop,
  Atom *out_type,
  uint8_t **out,
  size_t *out_len
) {
  *out = NULL;
  *out_len = 0;
  *out_type = None;
  Atom actual = None;
  int format = 0;
  unsigned long nitems = 0;
  unsigned long remaining = 0;
  unsigned char *data = NULL;
  /* 16 MiB of 32-bit units is enough for one clipboard image chunk. */
  int status = XGetWindowProperty(
    dpy, win, prop, 0, (1L << 22), False, AnyPropertyType,
    &actual, &format, &nitems, &remaining, &data
  );
  if (status != Success) {
    ppux_clipboard_set_error("XGetWindowProperty failed");
    return -1;
  }
  *out_type = actual;
  if (remaining > 0) {
    if (data) {
      XFree(data);
    }
    ppux_clipboard_set_error("clipboard image is too large");
    return -1;
  }
  size_t nbytes = 0;
  if (format == 8) {
    nbytes = (size_t)nitems;
  } else if (format == 16) {
    nbytes = (size_t)nitems * 2u;
  } else if (format == 32) {
    nbytes = (size_t)nitems * sizeof(long);
  }
  int rc = 0;
  if (nbytes > 0 && data) {
    uint8_t *copy = (uint8_t *)malloc(nbytes);
    if (!copy) {
      ppux_clipboard_set_error("out of memory");
      rc = -1;
    } else {
      memcpy(copy, data, nbytes);
      *out = copy;
      *out_len = nbytes;
    }
  }
  if (data) {
    XFree(data);
  }
  return rc;
}

static int x11_read_incr(
  Display *dpy,
  Window win,
  Atom prop,
  uint8_t **out,
  size_t *out_len
) {
  XDeleteProperty(dpy, win, prop);
  XFlush(dpy);
  uint8_t *buf = NULL;
  size_t len = 0;
  size_t cap = 0;
  X11PropMatch match = { win, prop };
  for (;;) {
    XEvent ev;
    if (!x11_wait(dpy, match_property, &match, 2000, &ev)) {
      free(buf);
      ppux_clipboard_set_error("timed out reading X11 INCR clipboard");
      return -1;
    }
    Atom actual = None;
    int format = 0;
    unsigned long nitems = 0;
    unsigned long remaining = 0;
    unsigned char *data = NULL;
    int status = XGetWindowProperty(
      dpy, win, prop, 0, (1L << 22), True, AnyPropertyType,
      &actual, &format, &nitems, &remaining, &data
    );
    if (status != Success) {
      free(buf);
      if (data) {
        XFree(data);
      }
      ppux_clipboard_set_error("XGetWindowProperty failed");
      return -1;
    }
    if (nitems == 0 || remaining > 0) {
      if (data) {
        XFree(data);
      }
      if (remaining > 0) {
        free(buf);
        ppux_clipboard_set_error("clipboard image is too large");
        return -1;
      }
      *out = buf;
      *out_len = len;
      return 0;
    }
    size_t nbytes = format == 8 ? (size_t)nitems : 0;
    if (nbytes > 0 && append_bytes(&buf, &len, &cap, data, nbytes) != 0) {
      XFree(data);
      free(buf);
      return -1;
    }
    if (data) {
      XFree(data);
    }
  }
}

static int x11_fetch_target(
  Display *dpy,
  Window win,
  Atom selection,
  Atom prop,
  Atom target,
  Atom incr,
  uint8_t **out,
  size_t *out_len,
  int *out_empty
) {
  *out = NULL;
  *out_len = 0;
  *out_empty = 0;
  XConvertSelection(dpy, selection, target, prop, win, CurrentTime);
  XFlush(dpy);
  X11SelMatch sel = { win, selection };
  XEvent ev;
  if (!x11_wait(dpy, match_selection, &sel, 2000, &ev)) {
    ppux_clipboard_set_error("timed out waiting for X11 clipboard");
    return -1;
  }
  if (ev.xselection.property == None) {
    *out_empty = 1;
    return 0;
  }
  Atom type = None;
  if (x11_copy_property(dpy, win, prop, &type, out, out_len) != 0) {
    return -1;
  }
  if (type == incr) {
    free(*out);
    *out = NULL;
    *out_len = 0;
    return x11_read_incr(dpy, win, prop, out, out_len);
  }
  XDeleteProperty(dpy, win, prop);
  return 0;
}

static int x11_get_image(
  uint8_t **out_bytes,
  size_t *out_size,
  int32_t *out_format
) {
  Display *dpy = XOpenDisplay(NULL);
  if (!dpy) {
    ppux_clipboard_set_error("XOpenDisplay failed");
    return PPUX_CLIP_UNAVAILABLE;
  }
  g_x_error = 0;
  XErrorHandler prev = XSetErrorHandler(x_error_handler);
  int screen = DefaultScreen(dpy);
  Window win = XCreateSimpleWindow(dpy, RootWindow(dpy, screen), 0, 0, 1, 1, 0, 0, 0);
  XSelectInput(dpy, win, PropertyChangeMask);
  Atom selection = XInternAtom(dpy, "CLIPBOARD", False);
  Atom prop = XInternAtom(dpy, "PPUX_CLIPBOARD", False);
  Atom png = XInternAtom(dpy, "image/png", False);
  Atom bmp = XInternAtom(dpy, "image/bmp", False);
  Atom incr = XInternAtom(dpy, "INCR", False);

  int rc = PPUX_CLIP_ERR;
  Atom targets[2] = { png, bmp };
  int32_t formats[2] = { PPUX_CLIP_FMT_PNG, PPUX_CLIP_FMT_BMP };
  for (int i = 0; i < 2; i++) {
    uint8_t *bytes = NULL;
    size_t size = 0;
    int empty = 0;
    if (x11_fetch_target(dpy, win, selection, prop, targets[i], incr, &bytes, &size, &empty) != 0) {
      free(bytes);
      rc = PPUX_CLIP_ERR;
      break;
    }
    if (g_x_error) {
      free(bytes);
      ppux_clipboard_set_error("X11 clipboard request failed");
      rc = PPUX_CLIP_ERR;
      break;
    }
    if (empty || size == 0) {
      free(bytes);
      if (i == 1) {
        ppux_clipboard_set_error("No image on the clipboard");
        rc = PPUX_CLIP_EMPTY;
      }
      continue;
    }
    *out_bytes = bytes;
    *out_size = size;
    *out_format = formats[i];
    rc = PPUX_CLIP_OK;
    break;
  }

  XSetErrorHandler(prev);
  XCloseDisplay(dpy);
  return rc;
}

int ppux_clipboard_platform_get_image(
  uint8_t **out_bytes,
  size_t *out_size,
  int32_t *out_format,
  int32_t *out_width,
  int32_t *out_height
) {
  (void)out_width;
  (void)out_height;
  const char *wayland = getenv("WAYLAND_DISPLAY");
  if (wayland && wayland[0]) {
    return wayland_get_image(out_bytes, out_size, out_format);
  }
  const char *display = getenv("DISPLAY");
  if (display && display[0]) {
    return x11_get_image(out_bytes, out_size, out_format);
  }
  ppux_clipboard_set_error("No display");
  return PPUX_CLIP_UNAVAILABLE;
}
