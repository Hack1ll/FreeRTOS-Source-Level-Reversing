# Context switch

The common scheduler chooses a task. The port layer makes the CPU actually run
it.

Cortex-M port를 보면 FreeRTOS context switch가 두 층으로 나뉘는 것을 볼 수
있습니다. `tasks.c`는 어떤 task가 다음인지 고르고, `port.c`는 CPU register와
stack pointer를 저장하고 복원합니다. SysTick은 시간을 앞으로 밀고, PendSV는
실제 switch를 낮은 priority exception으로 처리합니다.

The order in this part is:

1. [Cortex-M overview](cortex-m-overview.md)
2. [Initial stack frame](initial-stack-frame.md)
3. [SysTick](systick.md)
4. [PendSV](pendsv.md)

이 파트는 FreeRTOS를 "C 라이브러리"가 아니라 "CPU exception mechanism을 적극
사용하는 작은 커널"로 보게 만드는 구간입니다.

