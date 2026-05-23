# Synchronization primitives

Most synchronization objects in FreeRTOS are different faces of the same small
set of ideas: queues, lists, blocking, waking, and sometimes ownership.

Queue를 이해하면 semaphore와 mutex가 훨씬 쉬워집니다. Event group은 queue
계열은 아니지만, task를 event list에 넣고 조건이 만족되면 ready list로 돌려보낸
다는 점에서 같은 scheduler 언어를 씁니다.

The order in this part is:

1. [Queues](queues.md)
2. [Semaphores](semaphores.md)
3. [Mutexes](mutexes.md)
4. [Event groups](event-groups.md)

여기서 중요한 것은 API 이름보다 blocked task가 어느 list로 이동하는지입니다.

