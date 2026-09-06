%define count 1000

section .bss
output: resq count

global _start
section .text
_start:
	mov rax, count
	mov rbp, output

	mov rbx, 1
	mov rcx, 1

	mov [rbp], rbx
	mov [rbp + 8], rcx
	add rbp, 16

fibonacci:
	lea rdx, [rbx + rcx]
	mov [rbp], rdx
	mov rbx, rcx
	mov rcx, rdx
	add rbp, 8
	dec rax
	jnz fibonacci

exit:
	mov rax, 60
	mov rdi, 0
	syscall
