# FreeRTOS Source-Level Reversing

This repository contains a book-in-progress about the FreeRTOS kernel and its
insides.

이 프로젝트의 목표는 단순합니다. FreeRTOS 커널 소스를 한 줄씩 따라가며,
작은 RTOS 안에서 task, scheduler, interrupt, context switch, queue, heap이
어떻게 맞물리는지 이해하는 것입니다. 여기서 말하는 reversing은 타사
펌웨어를 분석한다는 뜻이 아니라, 공개된 소스 코드에서 실행 흐름과 자료구조의
의도를 다시 복원해 보는 공부 방식입니다.

If you are curious about what is under the hood of FreeRTOS, start with the
[Table of Contents](SUMMARY.md).

> [!NOTE]
> This is not official FreeRTOS documentation. It is a personal learning project
> inspired by the style of long-form kernel reading notes.

## Chapter status

The first pass focuses on a small and concrete subset:

- Kernel version: FreeRTOS-Kernel commit `a8c9d3515`
- Port: `portable/GCC/ARM_CM4F`
- Memory manager: `portable/MemMang/heap_4.c`
- Main path: list -> TCB -> task creation -> scheduler -> context switch ->
  queues -> heap

The repository does not include FreeRTOS source code. It also does not contain
third-party firmware, commercial binaries, exploit proof-of-concepts, Ghidra
projects, or copied source dumps.

## Requirements

You do not need to be an RTOS expert before reading these notes. It helps if you
are comfortable with:

- the C programming language;
- pointers and structures;
- a little bit of ARM Cortex-M exception terminology;
- reading short snippets of assembly.

The notes are written mostly in Korean, but file names, symbols, and short
explanations use English when that makes source lookup easier.

## Source code

FreeRTOS is intentionally not committed to this repository. If you want to
follow the references locally, clone the upstream kernel into the working copy:

```sh
git clone https://github.com/FreeRTOS/FreeRTOS-Kernel.git FreeRTOS-Kernel
cd FreeRTOS-Kernel
git checkout a8c9d3515
```

The `FreeRTOS-Kernel/` directory is ignored by git, so it can stay as a local
companion checkout while the published repository remains notes-only.

## How to read

Read [docs/00-preface.md](docs/00-preface.md) first if you want the motivation.
If you want the shortest technical path, start from
[docs/01-reading-map.md](docs/01-reading-map.md). The recommended order is:

1. FreeRTOS lists
2. Task Control Block
3. Task creation and task states
4. Ready lists and scheduler tick
5. Cortex-M context switch
6. Queues, semaphores, mutexes, and event groups
7. `heap_4.c`
8. GCC ARM Cortex-M4F port layer

Run the local documentation checks with:

```sh
tools/check-source-links.sh
```

## License

The notes and local tooling in this repository are released under the MIT
License. FreeRTOS itself is not included or relicensed by this repository; see
the upstream FreeRTOS repository for its license.
