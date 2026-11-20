#define _GNU_SOURCE

#include "clipboard_internal.h"

#include <errno.h>
#include <poll.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <wayland-client.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>

static void ppux_clipboard_x11_init(void) __attribute__((constructor));
static void ppux_clipboard_x11_init(void) {
  XInitThreads();
}

static pthread_mutex_t g_owner_mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_owner_cv = PTHREAD_COND_INITIALIZER;
static pthread_t g_owner_thread;
static int g_owner_live;
static volatile int g_owner_stop;
static int g_owner_status;
static uint8_t *g_png;
static size_t g_png_size;

static void owner_publish(int status, const char *err) {
  if (status < 0 && err) {
    ppux_clipboard_set_error(err);
  }
  pthread_mutex_lock(&g_owner_mu);
  g_owner_status = status;
  pthread_cond_signal(&g_owner_cv);
  pthread_mutex_unlock(&g_owner_mu);
}

static void owner_stop_joined(void) {
  if (!g_owner_live) {
    return;
  }
  g_owner_stop = 1;
  pthread_join(g_owner_thread, NULL);
  g_owner_live = 0;
  g_owner_stop = 0;
}

static int owner_install(const uint8_t *bytes, size_t size, void *(*thread_main)(void *)) {
  uint8_t *copy = (uint8_t *)malloc(size);
  if (!copy) {
    ppux_clipboard_set_error("out of memory");
    return PPUX_CLIP_ERR;
  }
  memcpy(copy, bytes, size);

  owner_stop_joined();
  free(g_png);
  g_png = copy;
  g_png_size = size;
  g_owner_stop = 0;

  pthread_mutex_lock(&g_owner_mu);
  g_owner_status = 0;
  pthread_mutex_unlock(&g_owner_mu);

  if (pthread_create(&g_owner_thread, NULL, thread_main, NULL) != 0) {
    free(g_png);
    g_png = NULL;
    g_png_size = 0;
    ppux_clipboard_set_error("clipboard thread failed");
    return PPUX_CLIP_ERR;
  }
  g_owner_live = 1;

  pthread_mutex_lock(&g_owner_mu);
  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  ts.tv_sec += 2;
  while (g_owner_status == 0) {
    if (pthread_cond_timedwait(&g_owner_cv, &g_owner_mu, &ts) == ETIMEDOUT) {
      break;
    }
  }
  int status = g_owner_status;
  pthread_mutex_unlock(&g_owner_mu);

  if (status != 1) {
    owner_stop_joined();
    free(g_png);
    g_png = NULL;
    g_png_size = 0;
    if (ppux_clipboard_last_error()[0] == '\0') {
      ppux_clipboard_set_error("clipboard write failed");
    }
    return PPUX_CLIP_ERR;
  }
  return PPUX_CLIP_OK;
}

/* ---------- X11 owner ---------- */

static int g_owner_x_error;
static Display *g_owner_dpy;
static XErrorHandler g_owner_prev_x_error;

/* Only swallow errors for this helper's Display. Other displays (the
 * LOVE/SDL window) keep the handler that was installed before us, and
 * we put that handler back on exit only if it is still ours.
 */
static int owner_x_error(Display *dpy, XErrorEvent *ev) {
  if (g_owner_dpy && dpy == g_owner_dpy) {
    g_owner_x_error = ev->error_code;
    return 0;
  }
  if (g_owner_prev_x_error) {
    return g_owner_prev_x_error(dpy, ev);
  }
  return 0;
}

static void owner_install_x_handler(void) {
  g_owner_dpy = NULL;
  g_owner_x_error = 0;
  g_owner_prev_x_error = XSetErrorHandler(owner_x_error);
}

static void owner_remove_x_handler(void) {
  XErrorHandler current = XSetErrorHandler(g_owner_prev_x_error);
  if (current != owner_x_error) {
    XSetErrorHandler(current);
  }
  g_owner_dpy = NULL;
  g_owner_prev_x_error = NULL;
}

static void x11_reply(Display *dpy, const XSelectionRequestEvent *req, Atom property) {
  XEvent ev;
  memset(&ev, 0, sizeof(ev));
  ev.type = SelectionNotify;
  ev.xselection.requestor = req->requestor;
  ev.xselection.selection = req->selection;
  ev.xselection.target = req->target;
  ev.xselection.property = property;
  ev.xselection.time = req->time;
  XSendEvent(dpy, req->requestor, False, 0, &ev);
  XFlush(dpy);
}

static size_t x11_chunk_bytes(Display *dpy) {
  size_t units = (size_t)XMaxRequestSize(dpy);
  if (units > 100) {
    units -= 100;
  }
  size_t chunk = units * 4u;
  if (chunk > 1024u * 1024u) {
    chunk = 1024u * 1024u;
  }
  if (chunk < 256u) {
    chunk = 256u;
  }
  return chunk;
}

typedef struct X11Incr {
  int active;
  Window requestor;
  Atom property;
  Atom type;
  size_t offset;
  size_t chunk;
} X11Incr;

static void x11_incr_write(Display *dpy, X11Incr *incr) {
  size_t left = (g_png_size > incr->offset) ? (g_png_size - incr->offset) : 0;
  size_t n = left < incr->chunk ? left : incr->chunk;
  if (n == 0 || !g_png) {
    XChangeProperty(
      dpy, incr->requestor, incr->property, incr->type,
      8, PropModeReplace, NULL, 0
    );
    incr->active = 0;
    return;
  }
  XChangeProperty(
    dpy, incr->requestor, incr->property, incr->type,
    8, PropModeReplace, g_png + incr->offset, (int)n
  );
  incr->offset += n;
  XFlush(dpy);
}

static void x11_serve_request(
  Display *dpy,
  const XSelectionRequestEvent *req,
  Atom atom_targets,
  Atom atom_png,
  Atom atom_incr,
  X11Incr *incr
) {
  Atom property = req->property;
  if (property == None) {
    property = req->target;
  }

  if (req->target == atom_targets) {
    long list[2];
    list[0] = (long)atom_targets;
    list[1] = (long)atom_png;
    XChangeProperty(
      dpy, req->requestor, property, XA_ATOM,
      32, PropModeReplace, (unsigned char *)list, 2
    );
    x11_reply(dpy, req, property);
    return;
  }

  if (req->target != atom_png || !g_png || g_png_size == 0) {
    x11_reply(dpy, req, None);
    return;
  }

  size_t chunk = x11_chunk_bytes(dpy);
  if (g_png_size <= chunk) {
    XChangeProperty(
      dpy, req->requestor, property, atom_png,
      8, PropModeReplace, g_png, (int)g_png_size
    );
    x11_reply(dpy, req, property);
    return;
  }

  long size32 = (long)(g_png_size & 0xFFFFFFFFu);
  XChangeProperty(
    dpy, req->requestor, property, atom_incr,
    32, PropModeReplace, (unsigned char *)&size32, 1
  );
  XSelectInput(dpy, req->requestor, PropertyChangeMask);
  incr->active = 1;
  incr->requestor = req->requestor;
  incr->property = property;
  incr->type = atom_png;
  incr->offset = 0;
  incr->chunk = chunk;
  x11_reply(dpy, req, property);
}

static void *x11_owner_main(void *unused) {
  (void)unused;
  owner_install_x_handler();
  Display *dpy = XOpenDisplay(NULL);
  if (!dpy) {
    owner_remove_x_handler();
    owner_publish(-1, "XOpenDisplay failed");
    return NULL;
  }
  g_owner_dpy = dpy;

  int screen = DefaultScreen(dpy);
  Window win = XCreateSimpleWindow(dpy, RootWindow(dpy, screen), 0, 0, 1, 1, 0, 0, 0);
  Atom clipboard = XInternAtom(dpy, "CLIPBOARD", False);
  Atom atom_targets = XInternAtom(dpy, "TARGETS", False);
  Atom atom_png = XInternAtom(dpy, "image/png", False);
  Atom atom_incr = XInternAtom(dpy, "INCR", False);

  XSetSelectionOwner(dpy, clipboard, win, CurrentTime);
  XFlush(dpy);
  if (g_owner_x_error || XGetSelectionOwner(dpy, clipboard) != win) {
    XDestroyWindow(dpy, win);
    XCloseDisplay(dpy);
    g_owner_dpy = NULL;
    owner_remove_x_handler();
    owner_publish(-1, "X11 clipboard ownership failed");
    return NULL;
  }
  owner_publish(1, NULL);

  X11Incr incr;
  memset(&incr, 0, sizeof(incr));
  int fd = ConnectionNumber(dpy);
  while (!g_owner_stop) {
    while (XPending(dpy)) {
      XEvent ev;
      XNextEvent(dpy, &ev);
      if (ev.type == SelectionClear
          && ev.xselectionclear.selection == clipboard
          && ev.xselectionclear.window == win) {
        g_owner_stop = 1;
        break;
      }
      if (ev.type == SelectionRequest && ev.xselectionrequest.owner == win) {
        XSelectionRequestEvent req = ev.xselectionrequest;
        x11_serve_request(dpy, &req, atom_targets, atom_png, atom_incr, &incr);
      } else if (incr.active
          && ev.type == PropertyNotify
          && ev.xproperty.window == incr.requestor
          && ev.xproperty.atom == incr.property
          && ev.xproperty.state == PropertyDelete) {
        x11_incr_write(dpy, &incr);
      }
    }
    if (g_owner_stop) {
      break;
    }
    struct pollfd pfd;
    pfd.fd = fd;
    pfd.events = POLLIN;
    pfd.revents = 0;
    int pr = poll(&pfd, 1, 100);
    if (pr < 0 && errno == EINTR) {
      continue;
    }
  }

  if (XGetSelectionOwner(dpy, clipboard) == win) {
    XSetSelectionOwner(dpy, clipboard, None, CurrentTime);
    XFlush(dpy);
  }
  XDestroyWindow(dpy, win);
  XCloseDisplay(dpy);
  g_owner_dpy = NULL;
  owner_remove_x_handler();
  return NULL;
}

/* ---------- Wayland owner ---------- */

typedef struct WlSetState {
  struct wl_seat *seat;
  struct wl_data_device_manager *manager;
} WlSetState;

static int g_wl_cancelled;

static void wl_set_source_target(void *data, struct wl_data_source *source, const char *mime) {
  (void)data;
  (void)source;
  (void)mime;
}

static void wl_set_source_send(
  void *data,
  struct wl_data_source *source,
  const char *mime,
  int32_t fd
) {
  (void)data;
  (void)source;
  if (mime && strcmp(mime, "image/png") == 0 && g_png && g_png_size > 0) {
    size_t off = 0;
    while (off < g_png_size) {
      ssize_t n = write(fd, g_png + off, g_png_size - off);
      if (n < 0 && errno == EINTR) {
        continue;
      }
      if (n <= 0) {
        break;
      }
      off += (size_t)n;
    }
  }
  close(fd);
}

static void wl_set_source_cancelled(void *data, struct wl_data_source *source) {
  (void)source;
  int *cancelled = data;
  if (cancelled) {
    *cancelled = 1;
  }
}

static void wl_set_source_dnd_drop(void *data, struct wl_data_source *source) {
  (void)data;
  (void)source;
}

static void wl_set_source_dnd_finished(void *data, struct wl_data_source *source) {
  (void)data;
  (void)source;
}

static void wl_set_source_action(void *data, struct wl_data_source *source, uint32_t action) {
  (void)data;
  (void)source;
  (void)action;
}

static const struct wl_data_source_listener wl_set_source_listener = {
  .target = wl_set_source_target,
  .send = wl_set_source_send,
  .cancelled = wl_set_source_cancelled,
  .dnd_drop_performed = wl_set_source_dnd_drop,
  .dnd_finished = wl_set_source_dnd_finished,
  .action = wl_set_source_action,
};

static void wl_set_device_offer(void *data, struct wl_data_device *device, struct wl_data_offer *id) {
  (void)data;
  (void)device;
  if (id) {
    wl_data_offer_destroy(id);
  }
}

static void wl_set_device_enter(
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

static void wl_set_device_leave(void *data, struct wl_data_device *device) {
  (void)data;
  (void)device;
}

static void wl_set_device_motion(
  void *data,
  struct wl_data_device *device,
  uint32_t time,
  wl_fixed_t x,
  wl_fixed_t y
) {
  (void)data; (void)device; (void)time; (void)x; (void)y;
}

static void wl_set_device_drop(void *data, struct wl_data_device *device) {
  (void)data;
  (void)device;
}

static void wl_set_device_selection(void *data, struct wl_data_device *device, struct wl_data_offer *id) {
  (void)data;
  (void)device;
  (void)id;
}

static const struct wl_data_device_listener wl_set_device_listener = {
  .data_offer = wl_set_device_offer,
  .enter = wl_set_device_enter,
  .leave = wl_set_device_leave,
  .motion = wl_set_device_motion,
  .drop = wl_set_device_drop,
  .selection = wl_set_device_selection,
};

static void wl_set_registry_global(
  void *data,
  struct wl_registry *registry,
  uint32_t name,
  const char *interface,
  uint32_t version
) {
  (void)version;
  WlSetState *st = data;
  if (!interface) {
    return;
  }
  if (!st->seat && strcmp(interface, wl_seat_interface.name) == 0) {
    st->seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
  } else if (!st->manager && strcmp(interface, wl_data_device_manager_interface.name) == 0) {
    st->manager = wl_registry_bind(registry, name, &wl_data_device_manager_interface, 1);
  }
}

static void wl_set_registry_remove(void *data, struct wl_registry *registry, uint32_t name) {
  (void)data;
  (void)registry;
  (void)name;
}

static const struct wl_registry_listener wl_set_registry_listener = {
  .global = wl_set_registry_global,
  .global_remove = wl_set_registry_remove,
};

static void *wayland_owner_main(void *unused) {
  (void)unused;
  g_wl_cancelled = 0;
  struct wl_display *dpy = wl_display_connect(NULL);
  if (!dpy) {
    owner_publish(-1, "Wayland connect failed");
    return NULL;
  }

  WlSetState st;
  memset(&st, 0, sizeof(st));
  struct wl_registry *registry = wl_display_get_registry(dpy);
  wl_registry_add_listener(registry, &wl_set_registry_listener, &st);
  if (wl_display_roundtrip(dpy) < 0 || !st.seat || !st.manager) {
    if (st.manager) {
      wl_data_device_manager_destroy(st.manager);
    }
    if (st.seat) {
      wl_seat_destroy(st.seat);
    }
    wl_registry_destroy(registry);
    wl_display_disconnect(dpy);
    owner_publish(-1, "Wayland clipboard is unavailable");
    return NULL;
  }

  struct wl_data_device *device = wl_data_device_manager_get_data_device(st.manager, st.seat);
  wl_data_device_add_listener(device, &wl_set_device_listener, NULL);
  struct wl_data_source *source = wl_data_device_manager_create_data_source(st.manager);
  wl_data_source_offer(source, "image/png");
  wl_data_source_add_listener(source, &wl_set_source_listener, &g_wl_cancelled);
  /* Serial 0 is accepted by compositors that do not require a focused surface. */
  wl_data_device_set_selection(device, source, 0);
  if (wl_display_roundtrip(dpy) < 0) {
    wl_data_source_destroy(source);
    wl_data_device_destroy(device);
    wl_data_device_manager_destroy(st.manager);
    wl_seat_destroy(st.seat);
    wl_registry_destroy(registry);
    wl_display_disconnect(dpy);
    owner_publish(-1, "Wayland clipboard ownership failed");
    return NULL;
  }
  owner_publish(1, NULL);

  int dpy_fd = wl_display_get_fd(dpy);
  while (!g_owner_stop && !g_wl_cancelled) {
    int prepared = 0;
    while (wl_display_prepare_read(dpy) != 0) {
      if (wl_display_dispatch_pending(dpy) < 0) {
        g_owner_stop = 1;
        break;
      }
    }
    if (!g_owner_stop) {
      prepared = 1;
    }
    if (g_owner_stop || g_wl_cancelled) {
      if (prepared) {
        wl_display_cancel_read(dpy);
      }
      break;
    }
    if (wl_display_flush(dpy) < 0 && errno != EAGAIN) {
      wl_display_cancel_read(dpy);
      break;
    }
    struct pollfd pfd;
    pfd.fd = dpy_fd;
    pfd.events = POLLIN;
    pfd.revents = 0;
    int pr = poll(&pfd, 1, 100);
    if (pr < 0 && errno == EINTR) {
      wl_display_cancel_read(dpy);
      continue;
    }
    if (pr > 0 && (pfd.revents & (POLLIN | POLLERR | POLLHUP))) {
      if (wl_display_read_events(dpy) < 0) {
        break;
      }
    } else {
      wl_display_cancel_read(dpy);
    }
    if (wl_display_dispatch_pending(dpy) < 0) {
      break;
    }
  }

  wl_data_source_destroy(source);
  wl_data_device_destroy(device);
  wl_data_device_manager_destroy(st.manager);
  wl_seat_destroy(st.seat);
  wl_registry_destroy(registry);
  wl_display_disconnect(dpy);
  return NULL;
}

int ppux_clipboard_platform_set_png(const uint8_t *bytes, size_t size) {
  const size_t max_bytes = 32u * 1024u * 1024u;
  if (!bytes || size == 0 || size > max_bytes) {
    ppux_clipboard_set_error("empty png");
    return PPUX_CLIP_ERR;
  }

  const char *wayland = getenv("WAYLAND_DISPLAY");
  const char *display = getenv("DISPLAY");
  if (wayland && wayland[0]) {
    int rc = owner_install(bytes, size, wayland_owner_main);
    if (rc == PPUX_CLIP_OK) {
      return rc;
    }
  }
  if (display && display[0]) {
    return owner_install(bytes, size, x11_owner_main);
  }
  if (wayland && wayland[0]) {
    return PPUX_CLIP_ERR;
  }
  ppux_clipboard_set_error("No display");
  return PPUX_CLIP_UNAVAILABLE;
}
