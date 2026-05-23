# Task management

A task is the unit that FreeRTOS schedules, blocks, wakes, and switches away
from.

이 파트에서는 task가 어떻게 태어나고, 어떤 list를 지나며, delay나 event wait
상태로 이동하는지 봅니다. 핵심 파일은 `FreeRTOS-Kernel/tasks.c`입니다. 이름은
하나의 파일이지만, 실제로는 scheduler state, TCB 초기화, delayed list 처리,
task priority 처리까지 커널의 많은 중심부가 여기에 들어 있습니다.

The order in this part is:

1. [Task creation](task-creation.md)
2. [Task states](task-states.md)
3. [Task delay](task-delay.md)

여기까지 읽으면 "task가 실행된다"는 말을 "TCB가 어떤 list에 있고, 어떤 stack
pointer를 가지고 있으며, scheduler가 언제 그것을 고르는가"로 바꿔 말할 수
있게 됩니다.

