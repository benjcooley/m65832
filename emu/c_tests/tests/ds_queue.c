// Test: Circular queue
// Expected: 10 (first enqueued value)
#define QUEUE_SIZE 16

struct Queue {
    int data[QUEUE_SIZE];
    int head;
    int tail;
    int count;
};

void queue_init(struct Queue *q) {
    q->head = 0;
    q->tail = 0;
    q->count = 0;
}

void queue_enqueue(struct Queue *q, int value) {
    if (q->count < QUEUE_SIZE) {
        q->data[q->tail] = value;
        q->tail = (q->tail + 1) & (QUEUE_SIZE - 1);
        q->count++;
    }
}

int queue_dequeue(struct Queue *q) {
    if (q->count > 0) {
        int value = q->data[q->head];
        q->head = (q->head + 1) & (QUEUE_SIZE - 1);
        q->count--;
        return value;
    }
    return -1;
}

int main(void) {
    struct Queue q;
    queue_init(&q);
    
    queue_enqueue(&q, 10);
    queue_enqueue(&q, 20);
    queue_enqueue(&q, 30);
    
    return queue_dequeue(&q);  // Should return 10 (FIFO)
}
