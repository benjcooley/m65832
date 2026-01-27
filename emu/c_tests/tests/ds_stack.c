// Test: Stack data structure
// Expected: 30 (last pushed value)
#define STACK_SIZE 16

struct Stack {
    int data[STACK_SIZE];
    int top;
};

void stack_init(struct Stack *s) {
    s->top = 0;
}

void stack_push(struct Stack *s, int value) {
    if (s->top < STACK_SIZE) {
        s->data[s->top] = value;
        s->top++;
    }
}

int stack_pop(struct Stack *s) {
    if (s->top > 0) {
        s->top--;
        return s->data[s->top];
    }
    return -1;
}

int stack_empty(struct Stack *s) {
    return s->top == 0;
}

int main(void) {
    struct Stack s;
    stack_init(&s);
    
    stack_push(&s, 10);
    stack_push(&s, 20);
    stack_push(&s, 30);
    
    return stack_pop(&s);  // Should return 30
}
