# Kernel objects

Every kernel has a few objects that everything else quietly depends on.

FreeRTOS의 경우 첫 번째 object는 task가 아니라 list입니다. Scheduler,
queue, semaphore, event group은 모두 task를 어떤 list에 넣고 빼는 방식으로
상태를 표현합니다. 그래서 이 파트는 `list.c`에서 시작해 `TCB_t`와 `Queue_t`로
천천히 올라갑니다.

The order in this part is:

1. [Doubly linked lists](list.md)
2. [Task Control Block](tcb.md)
3. [Queue object](queue.md)


