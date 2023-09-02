;-----------loader 所需要完成的工作  -------------------------------
; 1.内核的加载，从软件的fat12文件系统中加载内核到指定的内存地址
; 2.使用Bois中断查询硬件的信息写入到指定的内存地址，供内存后续的查询
; 3.切换cpu的工作模式，从实模式到保护模式再到IA-32e模式
; 4.最后调整到内核执行

[bits 16]

; 第一行代码所面临的问题就是，重定向的问题，loader代码的起始地址要如果约定，
; 依赖于loader被加载的位置，要与boot提前进行约定。

BaseOfKernelFile	equ	0x00
OffsetOfKernelFile	equ	0x100000

; 内核加载的临时转存区域，
BaseTmpOfKernelAddr	equ	0x00
OffsetTmpOfKernelFile	equ	0x7e00

RootDirSectors                  equ 14     ;根目录的扇区数量 （14 * 512 / 32）
SectorNumOfRootDirStart         equ 19     ; 根目录起始的扇区号
SectorNumOfFAT1Start            equ 1      ; FAT1开始的扇区编号
SectorBalance                   equ 17

section code vstart=0x10000

    ; 跳转到开始处开始执行
    jmp Label_Start

; 为了操作fat12文件系统，从中查询内核的代码文件，需要引入一些在boot中写的一些代码

; 从指定的多个扇区中读取数据到指定位置
; ax = 起始扇区编址（LBA）
; cl = 要读取的扇区数量
; es:bx = 读取数据的存放位置
Func_ReadOneSector:
    push bp
    mov bp, sp
    sub esp, 2
    mov byte [bp - 2], cl
    push bx
    mov bl, [BPB_SecPerTrk]
    div bl
    inc ah
    mov cl, ah
    mov dh, al
    shr al, 1
    mov ch, al
    and dh, 1
    pop bx
    mov dl, [BS_DrvNum]
Label_Go_On_Reading:
    mov ah, 2
    mov al, byte [bp - 2]
    int 0x13
    jc Label_Go_On_Reading
    add esp, 2
    pop bp
    ret

;========== get FAT Entry
; 根据给定的FAT表项索引，在FAT表中查询链表中的下一个索引
; 输入：
;       ax = 给定的FAT表项索引
; 输出：
;       ax = 下一个FAT表项的索引
Func_GetFATEntry:

	push	es
	push	bx
	push	ax
	mov	ax,	00
	mov	es,	ax
	pop	ax
	mov	byte	[Odd],	0
	mov	bx,	3
	mul	bx
	mov	bx,	2
	div	bx
	cmp	dx,	0
	jz	Label_Even
	mov	byte	[Odd],	1

Label_Even:

	xor	dx,	dx
	mov	bx,	[BPB_BytesPerSec]
	div	bx
	push	dx
	mov	bx,	8000h
	add	ax,	SectorNumOfFAT1Start
	mov	cl,	2
	call	Func_ReadOneSector

	pop	dx
	add	bx,	dx
	mov	ax,	[es:bx]
	cmp	byte	[Odd],	1
	jnz	Label_Even_2
	shr	ax,	4

Label_Even_2:
	and	ax,	0fffh
	pop	bx
	pop	es
	ret


; loader的代码这里开始执行
Label_Start:
    mov ax, cs
    mov ds, ax

; 为了将内核加载到0x100000的地址处，需要先进入big mode模式，初始化一个段寄存器fs
    cli ;关闭中断

; 开启A20地址线
    in al, 0x92
    or al, 0x2
    out 0x92, al

; 进入保护模式
    lgdt [gdt_ptr]
    mov eax, cr0
    or eax, 0x01
    mov cr0, eax

    mov ax, 0x10
    mov fs, ax

    mov eax, cr0
    and al, 0xfe
    mov cr0, eax

    sti ;退出保护模式后恢复中断

; 下一步就是从软盘中找到kerneL.bin并加装到指定的地址处
;=======	reset floppy

	xor	ah,	ah
	xor	dl,	dl
	int	13h

; ====== search kernel.bin
; 基本的工作方式就是从软盘中读取一个扇区的内容到指定的内容，
; 然后遍历该扇区中的所有的目录项，寻找和目标匹配的目录项
	mov	word	[SectorNo],	SectorNumOfRootDirStart

Lable_Search_In_Root_Dir_Begin:

	cmp	word	[RootDirSizeForLoop],	0
	jz	Label_No_KernelBin
	dec	word	[RootDirSizeForLoop]    ; 根目录的扇区数，确定了循环次数

	mov	ax,	00h
	mov	es,	ax
	mov	bx,	8000h
	mov	ax,	[SectorNo]
	mov	cl,	1
	call	Func_ReadOneSector              ; 读取一个扇区到0x8000地址处

	mov	si,	KernelFileName
	mov	di,	8000h                   ; 一个扇区内容所在的地址
	cld
	mov	dx,	10h                     ; 一个扇区512B（0x200），一个根目录项32B (0x20), 一个扇区共有 0x10个目录项

Label_Search_For_KernelBin:

	cmp	dx,	0
	jz	Label_Goto_Next_Sector_In_Root_Dir   ; 一个扇区遍历完成后没有找个，准备去下一个扇区寻找
	dec	dx
	mov	cx,	11                           ; 在根目录项中，文件占据11B，文件名8B，扩展名3B

Label_Cmp_FileName:

	cmp	cx,	0
	jz	Label_FileName_Found                  ; 成功比对出目标文件名
	dec	cx
	lodsb
	cmp	al,	byte	[es:di]                ; 一次只比较一个字节的内容
	jz	Label_Go_On                            ; 准备比较下一个字节的内容
	jmp	Label_Different                        ; 名字不同，准备比较下一个目录项

Label_Go_On:

	inc	di
	jmp	Label_Cmp_FileName

Label_Different:

	and	di,	0ffe0h
	add	di,	20h
	mov	si,	KernelFileName
	jmp	Label_Search_For_KernelBin

Label_Goto_Next_Sector_In_Root_Dir:

	add	word	[SectorNo],	1
	jmp	Lable_Search_In_Root_Dir_Begin

;=======	display on screen : ERROR:No LOADER Found

Label_No_KernelBin:                                       ; 遍历了整个根目录区也未找到目标文件的逻辑处理，打印一个错误消息，死循环

	mov	ax,	1301h
	mov	bx,	008ch
	mov	dx,	0100h
	mov	cx,	21
	push	ax
	mov	ax,	ds
	mov	es,	ax
	pop	ax
	mov	bp,	NoLoaderMessage
	int	10h
	jmp	$

;=======	found kernel.bin name in root director struct

Label_FileName_Found:                                   ; 找到了目标文件的逻辑处理

	mov	ax,	RootDirSectors
	and	di,	0ffe0h                          ; 32字节对齐，使得di为目录目录项的基地址，后续定位起始簇号使用
	add	di,	01ah                            ; 0x1a 起始簇号偏移
	mov	cx,	word	[es:di]
	push	cx
	add	cx,	ax
	add	cx,	SectorBalance

	mov	ax,	BaseTmpOfKernelAddr                    ;准备目标的加载地址为es:bx
	mov	es,	ax
	mov	bx,	OffsetTmpOfKernelFile

	mov	ax,	cx

Label_Go_On_Loading_File:                               ; 开始加载目标文件
	push	ax
	push	bx
	mov	ah,	0eh
	mov	al,	'.'
	mov	bl,	0fh
	int	10h                                     ; 使用中断显示一个字符

	pop	bx
	pop	ax

	mov	cl,	1
	call	Func_ReadOneSector                      ; 读取一个扇区内容到指定es:bx
	pop	ax

; 把读取到的内核内容转存到目标地址处
    push ax
    push cx
    push si
    push edi

    mov cx, 0x200 ; 一簇512（0x200）个字节
        ; 跳过fs的设置
    mov si,  OffsetTmpOfKernelFile ;转存的源地址, 每次转存是一样的
    mov edi, [OffsetOfKernelFileCount] ; 目标地址，每次执行转存时目标地址都不同，把目标地址记录在内存中

Label_Move_kernel:
    mov al, [es:si]
    mov fs:edi, al

    inc esi
    inc edi
    loop Label_Move_kernel

    pop edi
    pop si
    pop cx
    pop ax

	call	Func_GetFATEntry                        ; 计算文件的下一个簇号
	cmp	ax,	0fffh
	jz	Label_File_Loaded                       ; 文件完成加载

	push	ax
	mov	dx,	RootDirSectors                  ; 开始文件的下一个簇的加载
	add	ax,	dx
	add	ax,	SectorBalance
	add	bx,	[BPB_BytesPerSec]
	jmp	Label_Go_On_Loading_File

Label_File_Loaded:
;	jmp	BaseOfLoader:OffsetOfLoader             ; 跳转到目标位置开始执行

    hlt
; 查询硬件信息放入到指定位置
; 下面准备进入模式切换
; 进入32位保护模式
    cli  ;关闭中断，没有准备中断描述符表
    lgdt [gdt_ptr]
    mov eax, cr0
    or eax, 0x01
    mov cr0, eax
    ; 此时还只是16位的保护模式
    jmp dword 0x08:Label_Protection_Mode
Label_Protection_Mode:
    [bits 32] ; 以后的代码都是32位的编译方式
    ; 初始化所有的数据段
    mov eax, 0x10
    mov ds, ax
    mov fs, ax
    mov gs, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x7e00

; 进入ia-e32模式
; 跳过了ia-e32模式的校验
; 准备ia-e32模式下段描述符表
    lgdt [0x10000 + gdt64_ptr]

; 准备ia-e32模式下的页表，开启PAE模式, 设置cr3
; 设置页表就需要考虑到页表所在的内存位置，以及页表的内容，几级页表
; 页表所在的线性地址为0x90000, 是开启PAR模式下的页表，每一个页表项位是8个字节
        ; 每一个页表都是4kb的大小，表现在地址上就是相差0x1000
        ; 3级页表, 2MB的物理页面大小
        ; 页目录表的基地址为0x90000 , PML4E
	mov	dword	[0x90000],	0x91007
	mov	dword	[0x90004],	0x00000
        ; 两个页目录表项指向同一个页表
        ; 这样做是会存在2套不同的线性地址映射到同一个物理地址
        ; 0x0 - 0xbfffff  -> 0x0 - 0xbfffff
        ; 不想算了
	mov	dword	[0x90800],	0x91007
	mov	dword	[0x90804],	0x00000

        ; PDPT
	mov	dword	[0x91000],	0x92007
	mov	dword	[0x91004],	0x00000

        ; PDT + PTE
        ; 完成低12MB的物理地址的物理地址映射，填充了6个页表项
	mov	dword	[0x92000],	0x000083
	mov	dword	[0x92004],	0x000000

	mov	dword	[0x92008],	0x200083
	mov	dword	[0x9200c],	0x000000

	mov	dword	[0x92010],	0x400083
	mov	dword	[0x92014],	0x000000

	mov	dword	[0x92018],	0x600083
	mov	dword	[0x9201c],	0x000000

	mov	dword	[0x92020],	0x800083
	mov	dword	[0x92024],	0x000000

	mov	dword	[0x92028],	0xa00083
	mov	dword	[0x9202c],	0x000000


        ; 开启pae模式，置位cr4中的第5位
        mov eax, cr4
        or eax, 0x20
	mov cr4, eax

        mov eax, 0x90000
        mov cr3, eax

; 开启ia-e32模式

	mov ecx, 0x0c0000080		;IA32_EFER
	rdmsr

	or eax,	0x100
	wrmsr

; 开启分页, 进入ia-e32模式
       	mov eax, cr0
        or eax, 0x8000_0001
	mov	cr0,	eax

; 此时还是32位兼容模式
; 执行一次远跳转设置CS寄存器以及清除指令流水线
        jmp 0x08:Label_IA_E32
Label_IA_E32:
        [bits 64]
        ; 设置各个段寄存器
        mov ax, 0x10
        mov ds, ax
        mov es, ax
        mov gs, ax
        mov fs, ax
        mov ss, ax
        mov rsp, 0x7e00




; 定义加载所需要的数据
section data
    BaseBootMessage   db 'Start Boot。。。。'
    NoLoaderMessage   db 'There is not loader.bin'
    FileFoundMessage  db 'Found the loader.bin'

    Odd               db 0
    SectorNo          dw 0
    RootDirSizeForLoop dw RootDirSectors
    KernelFileName   db 'KERNEL  BIN'
    OffsetOfKernelFileCount dd OffsetOfKernelFile
; 段描述符相关的定义
section gdt32 align=8
gdt32:
    dd 0x0, 0x0 ;空段            0x0
    dd 0x0000ffff, 0x00cf9a00,   ;代码段 0x08
    dd 0x0000ffff, 0x00cf9200,   ;数据段 0x10

gdt_ptr:
    dw ($ - gdt32 - 1)
    dd 0x10000 + gdt32

section gdt64 align=8
gdt64:
    dd 0x0, 0x0 ; 空段
    dd 0x00000000, 0x00209800   ; 代码段 0x08
    dd 0x00000000, 0x00209200   ; 数据段 0x10

gdt64_ptr:
    dw ($ - gdt64 - 1)
    dd 0x10000 + gdt64

; fat12文件格式相关得定义
section fat12
    BS_OEMName        db 'MINEboot'
    BPB_BytesPerSec   dw 512
    BPB_SecPerClus    db 1
    BPB_RsvdSecCnt    dw 1
    BPB_NumFATs       db 2
    BPB_RootEntCnt    dw 224
    BPB_TolSec16      dw 2880
    BPB_Media         db 0xf0
    BPB_FATSz16       dw 9
    BPB_SecPerTrk     dw 18
    BPB_NumHeads      dw 2
    BPB_HiddSec       dd 0
    BPB_TolSec32      dd 0
    BS_DrvNum         db 0
    BS_Reserved1      db 0
    BS_BootSig        db 0x29
    BS_VolId          dd 0
    BS_VolLab         db 'boot loader'
    BS_FileSysType    db 'FAT12'




