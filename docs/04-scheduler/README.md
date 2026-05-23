# Scheduler

The scheduler answers one question again and again: which task should run next?

FreeRTOS의 scheduler는 복잡한 자료구조를 많이 쓰지 않습니다. Priority별 ready
list를 유지하고, tick이 지날 때 delayed task를 깨우고, context switch 시점에
다음 `TCB_t`를 고릅니다. 단순하지만 작동 방식은 꽤 선명합니다.

The order in this part is:

1. [Ready lists](ready-lists.md)
2. [The tick](tick.md)
3. [Choosing the next context](context-selection.md)

이 파트의 끝에서 중요한 이름은 하나입니다: `pxCurrentTCB`. Scheduler가 이
포인터를 바꾸면, port layer는 그 task의 stack에서 register state를 복원합니다.

