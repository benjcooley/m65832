// Test: Simple growable vector (fixed capacity)
// Expected: 60 (10+20+30)
#define MAX_CAPACITY 16

struct Vector {
    int data[MAX_CAPACITY];
    int size;
};

void vec_init(struct Vector *v) {
    v->size = 0;
}

void vec_push(struct Vector *v, int value) {
    if (v->size < MAX_CAPACITY) {
        v->data[v->size] = value;
        v->size++;
    }
}

int vec_get(struct Vector *v, int index) {
    if (index >= 0 && index < v->size) {
        return v->data[index];
    }
    return -1;
}

int vec_size(struct Vector *v) {
    return v->size;
}

int main(void) {
    struct Vector v;
    vec_init(&v);
    
    vec_push(&v, 10);
    vec_push(&v, 20);
    vec_push(&v, 30);
    
    // Sum all elements
    int sum = 0;
    for (int i = 0; i < vec_size(&v); i++) {
        sum += vec_get(&v, i);
    }
    return sum;
}
