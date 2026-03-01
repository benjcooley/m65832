// Test: Branch target codegen bug
// The M65832 compiler generates incorrect branch targets (0x0aeb1bb0)
// for certain code patterns involving:
//   - rb_tree insertion with inlined comparison callbacks
//   - switch statements with multiple complex cases
//   - timerqueue_add -> rb_add_cached -> __rb_insert
//
// Observed in kernel: timerqueue_add, printk_get_console_flush_type
// Always jumps to the same garbage address 0x0aeb1bb0.
//
// This test uses a simplified rb-tree insertion pattern to reproduce.

#define UART_DATA    (*(volatile unsigned int *)0x10006000)
#define UART_STATUS  (*(volatile unsigned int *)0x10006004)
#define UART_TXRDY   0x02

static void putc(char c) {
    while (!(UART_STATUS & UART_TXRDY))
        ;
    UART_DATA = c;
}
static void puts(const char *s) { while (*s) putc(*s++); }
static void puthex(unsigned int v) {
    static const char hex[] = "0123456789abcdef";
    putc('0'); putc('x');
    for (int i = 28; i >= 0; i -= 4)
        putc(hex[(v >> i) & 0xf]);
}

/* ---- Minimal rb-tree-like structure ---- */

struct rb_node {
    unsigned long __parent_color;
    struct rb_node *left;
    struct rb_node *right;
};

struct rb_root {
    struct rb_node *node;
};

struct rb_root_cached {
    struct rb_root rb_root;
    struct rb_node *leftmost;
};

#define RB_RED   0
#define RB_BLACK 1

#define rb_parent(r)   ((struct rb_node *)((r)->__parent_color & ~3))
#define rb_color(r)    ((r)->__parent_color & 1)
#define rb_set_parent_color(n, p, c) \
    (n)->__parent_color = (unsigned long)(p) | (c)

static inline void rb_set_black(struct rb_node *rb)
{
    rb->__parent_color |= RB_BLACK;
}

/* Simplified insert: just link left or right based on comparison */
static __attribute__((noinline)) int
rb_add_cached(struct rb_node *node, struct rb_root_cached *root,
              int (*less)(struct rb_node *, const struct rb_node *))
{
    struct rb_node **link = &root->rb_root.node;
    struct rb_node *parent = (void *)0;
    int leftmost = 1;

    while (*link) {
        parent = *link;
        if (less(node, parent)) {
            link = &parent->left;
        } else {
            link = &parent->right;
            leftmost = 0;
        }
    }

    node->__parent_color = (unsigned long)parent | RB_RED;
    node->left = (void *)0;
    node->right = (void *)0;
    *link = node;

    if (leftmost)
        root->leftmost = node;

    return leftmost;
}

/* ---- Timer queue structure ---- */

struct timerqueue_node {
    struct rb_node node;
    unsigned long long expires;
};

struct timerqueue_head {
    struct rb_root_cached rb_root;
};

#define container_of(ptr, type, member) \
    ((type *)((char *)(ptr) - __builtin_offsetof(type, member)))
#define rb_entry(ptr, type, member) container_of(ptr, type, member)
#define __node_2_tq(_n) rb_entry((_n), struct timerqueue_node, node)

static inline int __timerqueue_less(struct rb_node *a, const struct rb_node *b)
{
    return __node_2_tq(a)->expires < __node_2_tq(b)->expires;
}

/* This is the function that crashes in the kernel */
static __attribute__((noinline)) int
timerqueue_add(struct timerqueue_head *head, struct timerqueue_node *node)
{
    return rb_add_cached(&node->node, &head->rb_root, __timerqueue_less);
}

/* ---- Switch statement pattern ---- */

enum prio { PRIO_NORMAL = 0, PRIO_EMERGENCY = 1, PRIO_PANIC = 2 };

struct flush_type {
    int nbcon_atomic;
    int nbcon_offload;
    int legacy_direct;
    int legacy_offload;
};

static volatile int have_nbcon = 0;
static volatile int have_boot = 1;
static volatile int have_legacy = 1;
static volatile int kthreads_running = 0;
static volatile int irqwork_blocked = 0;
static volatile int legacy_allow_panic = 0;
static volatile enum prio default_prio = PRIO_NORMAL;

/* This is the other function that crashes */
static __attribute__((noinline)) void
get_flush_type(struct flush_type *ft)
{
    ft->nbcon_atomic = 0;
    ft->nbcon_offload = 0;
    ft->legacy_direct = 0;
    ft->legacy_offload = 0;

    switch (default_prio) {
    case PRIO_NORMAL:
        if (have_nbcon && !have_boot) {
            if (kthreads_running && !irqwork_blocked)
                ft->nbcon_offload = 1;
            else
                ft->nbcon_atomic = 1;
        }
        if (have_legacy || have_boot) {
            ft->legacy_direct = 1;
        }
        break;

    case PRIO_EMERGENCY:
        if (have_nbcon && !have_boot)
            ft->nbcon_atomic = 1;
        if (have_legacy || have_boot) {
            ft->legacy_direct = 1;
        }
        break;

    case PRIO_PANIC:
        if (have_nbcon && !have_boot)
            ft->nbcon_atomic = 1;
        if (have_legacy || have_boot) {
            ft->legacy_direct = 1;
            if (ft->nbcon_atomic && !legacy_allow_panic)
                ft->legacy_direct = 0;
        }
        break;

    default:
        puts("BAD PRIO\r\n");
        break;
    }
}

int main(void)
{
    int result;

    puts("=== Test 1: timerqueue_add ===\r\n");
    {
        struct timerqueue_head head = { .rb_root = { .rb_root = { .node = 0 }, .leftmost = 0 } };
        struct timerqueue_node n1 = { .expires = 100 };
        struct timerqueue_node n2 = { .expires = 50 };
        struct timerqueue_node n3 = { .expires = 200 };

        n1.node.left = 0; n1.node.right = 0; n1.node.__parent_color = 0;
        n2.node.left = 0; n2.node.right = 0; n2.node.__parent_color = 0;
        n3.node.left = 0; n3.node.right = 0; n3.node.__parent_color = 0;

        result = timerqueue_add(&head, &n1);
        puts("add n1(100): leftmost="); puthex(result); puts("\r\n");
        if (!result) { puts("FAIL\r\n"); return 1; }

        result = timerqueue_add(&head, &n2);
        puts("add n2(50): leftmost="); puthex(result); puts("\r\n");
        if (!result) { puts("FAIL\r\n"); return 2; }

        result = timerqueue_add(&head, &n3);
        puts("add n3(200): leftmost="); puthex(result); puts("\r\n");
        /* n3 should NOT be leftmost (200 > 50) */
        if (result) { puts("FAIL\r\n"); return 3; }

        puts("timerqueue_add OK\r\n");
    }

    puts("\r\n=== Test 2: switch/flush_type ===\r\n");
    {
        struct flush_type ft;

        default_prio = PRIO_NORMAL;
        get_flush_type(&ft);
        puts("NORMAL: legacy_direct="); puthex(ft.legacy_direct);
        puts(" nbcon_atomic="); puthex(ft.nbcon_atomic); puts("\r\n");
        if (ft.legacy_direct != 1) { puts("FAIL\r\n"); return 4; }

        default_prio = PRIO_EMERGENCY;
        get_flush_type(&ft);
        puts("EMERGENCY: legacy_direct="); puthex(ft.legacy_direct); puts("\r\n");
        if (ft.legacy_direct != 1) { puts("FAIL\r\n"); return 5; }

        default_prio = PRIO_PANIC;
        get_flush_type(&ft);
        puts("PANIC: legacy_direct="); puthex(ft.legacy_direct); puts("\r\n");
        /* With have_nbcon=0, nbcon_atomic=0, so legacy_direct should be 1 */
        if (ft.legacy_direct != 1) { puts("FAIL\r\n"); return 6; }

        puts("switch/flush_type OK\r\n");
    }

    puts("\r\nAll tests passed!\r\n");
    return 0;
}
