.code16
.org 0

.text

.global _start
_start:
    cli

    /* segment setup */
    mov %cs, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %fs
    mov %ax, %gs
    mov %ax, %ss

    /* place stack pointer in middle of free memory area */
    movw $0x3000, %sp

    /* save drive number to read kernel later */
    mov %dl, drive_num

    sti

    /* should print TETRIS TIME */
    movw $welcome_str, %si
    call print

    /* read kernel into memory at 0x10000 (segment 0x1000).
       kernel binary has been placed on the disk directly after the first sector
       reading $20 * num_sectors sectors after (value in %cx)
     */
    movw $20, %cx
    movb drive_num, %dl
    movw $disk_packet, %si
    movw $0x1000, segment
    movw $1, sector
sector_loop:
    movb $0x42, %ah
    int $0x13
    /*jc disk_error*/
    jc read_floppy /* fallback to INT 13h 0x02 */

    addw $64, sector
_ret_read_floppy:
    addw $0x8000, offset
    jnc sector_same_segment

    /* increment segment, reset offset if on different segment */
    addw $0x1000, segment
    movw $0x0000, offset
sector_same_segment:
    /* decrements %cx and loops if nonzero */
    loop sector_loop

    /* video mode: 320x200 @ 16 colors */
    movb $0x00, %ah
    movb $0x13, %al
    int $0x10

    /* enable A20 line */
    cli

    /* read and save state */
    call enable_a20_wait0
    movb $0xD0, %al
    outb $0x64
    call enable_a20_wait1
    xorw %ax, %ax
    inb $0x60

    /* write new state with A20 bit set (0x2) */
    pushw %ax
    call enable_a20_wait0
    movb $0xD1, %al
    outb $0x64
    call enable_a20_wait0
    popw %ax
    orw $0x2, %ax
    outb $0x60

    /* enable PE flag */
    movl %cr0, %eax
    orl $0x1, %eax
    movl %eax, %cr0

    /* jmp to flush prefetch queue */
    jmp flush
flush:
    lidt idt
    lgdt gdtp

    movw $(gdt_data_segment - gdt_start), %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %es
    movw %ax, %fs
    movw %ax, %gs
    movw %ax, %ss
    movl $0x3000, %esp
    ljmp $0x8, $entry32

.code32
entry32:
    /* jump to kernel loaded at 0x10000 */
    movl $0x10000, %eax
    jmpl *%eax

_loop:
    jmp _loop

.code16
enable_a20_wait0:
    xorw %ax, %ax
    inb $0x64
    btw $1, %ax
    jc enable_a20_wait0
    ret

enable_a20_wait1:
    xorw %ax, %ax
    inb $0x64
    btw $0, %ax
    jnc enable_a20_wait1
    ret

/*
; read 64 segs beginning from LBA# [sector]
; from floppy and store it at [segment]:[offset]
; And Intel syntax still is >>> AT&T, so I shall
; [at] you, jdah :D
*/
read_floppy:
/*	; I will destroy a load of registers, save them */
	pushw %ax
	pushw %bx
	pushw %cx
	pushw %dx
	pushw %es
	pushw %di
	
	movw segment, %es
	movw offset, %bx
/*	; DI= no. of segments to read */
	movw num_sectors, %di
	
_try_read:
/*	; Calculate CHS address from LBA
	; CHS: 80 Cylinders, each contain
	; 2 Heads, with 18 Sectors each */
	movw sector, %ax
	movw $0, %dx
	divw sectors_per_head
/*	; DX=remainder=S in CHS */
	movb %dl, %cl
/*	; AX=quotient=Head count from the start of disk */
	movw $0, %dx
	divw heads_per_cyl /* this could be a shift-right also */
	movb %dh, %ch
	movb %dl, %dh
	
	movw %di, %ax
	movb $2, %ah
	movb drive_num, %dl
	int $0x13
	jnc _read_ok
	
	movw $disk_error_str, %si
	call print
/*	; Me rn: */
	cli
	hlt
	
_read_ok:
/*	; who needs status codes? */
	movb $0, %ah
	addw %ax, sector
	addw %ax, %bx
	subw %ax, %di
	jnz _try_read
	
	popw %di
	popw %es
	popw %dx
	popw %cx
	popw %bx
	popw %ax
	jmp _ret_read_floppy

/* prints string in %ds:si */
print:
    xorb %bh, %bh
    movb $0x0E, %ah

    lodsb

    /* NULL check */
    cmpb $0, %al
    je 1f

    /* print %al to screen */
    int $0x10
    jmp print

1:  ret

welcome_str:
    .asciz "TETRIS TIME\n"
disk_error_str:
    .asciz "DISK ERROR\n"

/* SAVED DRIVE NUMBER TO READ FROM */
drive_num:
    .word 0x0000

/* INT 13H PACKET */
disk_packet:
    .byte 0x10
    .byte 0x00
num_sectors:
    .word 0x0040
offset:
    .word 0x0000
segment:
    .word 0x0000
sector:
    .quad 0x00000000

/* CHS geometry */
sectors_per_head:
	.word 18
heads_per_cyl:
	.word 2

/* GDT */
.align 16
gdtp:
    .word gdt_end - gdt_start - 1
    /* .long (0x07C0 << 4) + gdt */
    .long gdt_start

.align 16
gdt_start:
gdt_null:
    .quad 0
gdt_code_segment:
    .word 0xffff
    .word 0x0000
    .byte 0x00
    .byte 0b10011010
    .byte 0b11001111
    .byte 0x00
gdt_data_segment:
    .word 0xffff
    .word 0x0000
    .byte 0x00
    .byte 0b10010010
    .byte 0b11001111
    .byte 0x00
gdt_end:

/* IDT */
idt:
    .word 0
    .long 0

/* MBR BOOT SIGNATURE */
.fill 510-(.-_start), 1, 0
.word 0xAA55
