void session_set(char *key, char *val, bool copy);
char* session_get(char *key, char *def);
void box_init(box *b, int x, int y, int w, int h);
void box_free(box *b);
ubyte box_adjacent(box *s, int x, int y, int w, int h);
ubyte box_adjacent_within(box *s, int x, int y, int w, int h);
ubyte nearest_side(int ax, int ay, int aw, int ah, int bx, int by, int bw, int bh);
bool region_overlap_y(int ax, int ay, int aw, int ah, int bx, int by, int bw, int bh);
bool region_overlap_x(int ax, int ay, int aw, int ah, int bx, int by, int bw, int bh);
bool box_intersect(box *s, int x, int y, int width, int height);
char* grid_dump(grid *g);
void grid_load(grid *g, char *desc);
void grid_snapshot(grid *g, int id);
grid* grid_create(int w, int h);
void grid_free(grid *g);
grid *grid_copy(grid *g);
void grid_make_gap(grid *g, int x, int y, int w, int h, box *except);
bool grid_fill_gap(grid *g, int x, int y, int w, int h, box *except);
bool grid_check_boxes(grid *g);
bool grid_check_empty(grid *g);
bool grid_check(grid *g);
bool grid_autocommit(grid *g, grid *cpy);
bool grid_insert(grid *g, int x, int y, int w, int h);
bool grid_remove(grid *g, int index);
bool grid_resize(grid *g, int index, int x, int y, int w, int h);
bool grid_adjust(grid *g, int w, int h);
void grid_hide(grid *g);
void grid_show(grid *g);
void grid_configure(grid *g);
box* grid_box_by_region(grid *g, int x, int y, int w, int h);
ucell rule_match(rule *r, char *class, char *name, char *role, char *type, char *tag);
rule* rule_find(char *class, char *name, char *role, char *type, char *tag);
rule* rule_create(ucell rflags, char *class, char *name, char *role, char *type, char *tag, byte desktop, ucell setflags, ucell clrflags, ucell flipflags, int x, int y, int w, int h, int f, int cols, int rows);
void window_name(Window win, char *pad);
void window_class(Window win, char *pad);
void window_role(Window win, char *pad);
void window_tag(Window win, char *pad);
bool window_struts(Window win, ucell *l, ucell *r, ucell *t, ucell *b);
profile* profile_get(Window w);
void profile_set(Window w, profile *p);
void sanity_cb(hash *h, char *key, void *val);
void hook_run(ucell hook);
void sanity();
int window_get_state(Window w);
ucell window_get_flags(Window w);
int window_get_desktop(Window w);
profile* profile_update(Window w, bool refresh);
void profile_free(profile *p);
void profile_purge(Window w);
bool window_manage(profile *p);
bool window_visible(profile *p);
void window_set_state(profile *p, int state);
void window_set_flags(profile *p, ucell flag);
void window_clr_flags(profile *p, ucell flag);
void window_set_desktop(profile *p, int d);
void window_update_desktop(profile *p, int d);
rule* window_rule(profile *p);
rule* window_prepare(profile *p, ubyte refresh, rule *r);
void window_track(profile *p);
void window_raise_kids(Window w, Window except, Window *wins, ucell num, Window *trans, winlist *local, ubyte *used, ubyte *attrok, ubyte *view, ubyte *manage);
void window_raise(profile *p);
void window_focus(profile *p);
void window_check_visible(profile *p);
box* window_configure(profile *p, ucell mask, int x, int y, int w, int h, int b, rule *r, winlist *sibs);
box* window_restore(profile *p);
void window_iconify(profile *p);
ubyte ewmh_cb(Window win, void *ptr);
void ewmh_windows();
void ewmh_desktops();
void ewmh();
ubyte desktop_rescue(Window w, void *ptr);
ubyte desktop_raise_cb(Window w, void *ptr);
void desktop_raise(int d);
bool desktop_refresh_cb(Window w, void *ptr);
void desktop_configure(int d);
bool update_struts_cb(Window w, void *ptr);
void update_struts();
void window_activate(profile *p, bool refresh);
void window_activate_last();
bool parse_flags_type(hash *args, char *name, ucell *f);
bool parse_flags(hash *args, ucell *sf, ucell *cf, ucell *tf);
ubyte parse_mode(hash *args);
char* parse_direction(hash *args);
bool parse_int(hash *args, char *name, int *r);
bool op_split(char *in, autostr *out);
bool op_size(char *in, autostr *out);
bool op_remove(char *in, autostr *out);
bool op_overlay(char *in, autostr *out);
rule* parse_rule(hash *args);
bool op_rule(char *in, autostr *out);
bool op_hook(char *in, autostr *out);
bool op_config_cb(Window w, void *ptr);
bool op_config(char *in, autostr *out);
bool op_reset_cb(Window w, void *ptr);
bool op_reset(char *in, autostr *out);
void op_show_rules(autostr *out);
void op_show_grid(autostr *out);
void op_show_hooks(autostr *out);
bool op_show(char *in, autostr *out);
bool op_focus(char *in, autostr *out);
void grabs();
void event_KeyPress(XEvent *e);
void event_KeyRelease(XEvent *e);
void event_ButtonPress(XEvent *e);
void event_ButtonRelease(XEvent *e);
void event_MotionNotify(XEvent *e);
void event_EnterNotify(XEvent *e);
void event_LeaveNotify(XEvent *e);
void event_FocusIn(XEvent *e);
void event_FocusOut(XEvent *e);
void event_KeymapNotify(XEvent *e);
void event_Expose(XEvent *e);
void event_GraphicsExpose(XEvent *e);
void event_NoExpose(XEvent *e);
void event_VisibilityNotify(XEvent *e);
void event_CreateNotify(XEvent *e);
void event_DestroyNotify(XEvent *e);
void event_UnmapNotify(XEvent *e);
void event_MapNotify(XEvent *e);
void event_MapRequest(XEvent *e);
void event_ReparentNotify(XEvent *e);
void event_ConfigureNotify(XEvent *e);
void event_ConfigureRequest(XEvent *e);
void event_GravityNotify(XEvent *e);
void event_ResizeRequest(XEvent *e);
void event_CirculateNotify(XEvent *e);
void event_CirculateRequest(XEvent *e);
void event_PropertyNotify(XEvent *e);
void event_SelectionClear(XEvent *e);
void event_SelectionRequest(XEvent *e);
void event_SelectionNotify(XEvent *e);
void event_ColormapNotify(XEvent *e);
void event_ClientMessage(XEvent *e);
void event_MappingNotify(XEvent *e);
void event_GenericEvent(XEvent *e);
void timeout(int sig);
bool insert_command(ucell code, char* cmd);
ubyte setup_window(Window win, void *ptr);
int main(int argc, char *argv[]);
