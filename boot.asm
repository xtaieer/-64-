[bits 16]
org 0x7c00

BaseOfStack equ 0x7c00

RootDirSectors                  equ 14     ;根目录的扇区数量 （14 * 512 / 32）
SectorNumOfRootDirStart         equ 19     ; 根目录起始的扇区号
SectorNumOfFAT1Start            equ 1      ; FAT1开始的扇区编号
SectorBalance                   equ 17

    jmp Label_Start
    nop
    BS_OEMName        db 'MINEboot'
    BPB_BytesPreSec   dw 512
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



Label_Start:
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, BaseOfStack

; clear screen
    mov ax, 0x0600
    mov bx, 0x0700
    mov cx, 0
    mov dx, 0x184
    int 0x10

    mov ax, 0x0200
    mov bx, 0x0
    mov dx, 0
    int 0x10

    mov ax, 0x1301
    mov bx, 0xf
    mov dx, 0
    mov cx, 10
    push ax
    mov ax, ds
    mov es, ax
    pop ax

    mov bp, BaseBootMessage
    int 0x10

; ====== search loader.bin
; 基本的工作方式就是从软盘中读取一个扇区的内容到指定的内容，
; 然后遍历该扇区中的所有的目录项，寻找和目标匹配的目录项
    mov word [SectorNo], SectorNumOfRootDirStart  ; 当前要查询的扇区号

Label_Search_In_Root_Dir_Begin:
    cmp word [RootDirSizeForLoop], 0
    jz Label_No_LoaderBin      ;已经遍历完了所有的扇区
    dec word [RootDirSizeForLoop]

    mov ax, 0
    mov es, ax
    mov bx, 0x8000
    mov ax, [SectorNo]
    mov cl, 1
    call Func_ReadOneSector

    mov si, LoaderFileName
    mov di, 0x8000
    cld
    mov dx, 0x10      ; 比较次数  , 512 / 32  = 16 = 0x10 一个扇区所拥有的目录项的个数

Label_Search_For_LoaderBin:
    cmp dx, 0
    jz Label_Goto_Next_Sector_In_Root_Dir
    dec dx
    mov cx, 11      ; 一个目录项中名字的长度为11个字节

Label_Cmp_FileName:
    cmp cx, 0
    jz Label_FileName_Found
    dec cx
    lodsb
    cmp al, byte [es:di]
    jz Label_Go_On
    jmp Label_Different

Label_Go_On:
    inc di
    jmp Label_Cmp_FileName

Label_Different:
    and di, 0xffe0 ; 32位对齐
    add di, 0x20   ; 下一个目录项
    mov si, LoaderFileName
    jmp Label_Search_For_LoaderBin   ; 开始下一个目录项的查询

Label_Goto_Next_Sector_In_Root_Dir:
    add word [SectorNo], 1
    jmp Label_Search_In_Root_Dir_Begin

Label_No_LoaderBin:
    mov ax, 0x1301
    mov bx, 0x8c
    mov dx, 0x100
    mov cx, 23
    push ax
    mov ax, ds
    mov es, ax
    pop ax

    mov bp, NoLoaderMessage
    int 0x10
    jmp $

Label_FileName_Found:
    mov ax, RootDirSectors
    and di, 0xffe0
    add di, 0x1a
    mov cx, word [es:di]
    push cx
    add cx, ax
    add cx, SectorBalance
    mov ax, BaseOfLoader
    mov es, ax
    mov bx, OffsetOfLoader
    mov ax, cx

Label_Go_On_Loading_File:
    push ax
    push bx
    mov ah, 0x0e
    mov al, '.'
    mov bl, 0x0f
    int 0x10

    pop bx
    pop ax

    mov cl, 1
    call Func_ReadOneSector
    pop ax
    call Func_GetFATEntry
    cmp ax, 0x0fff
    jz Label_File_Loaded
    push ax
    mov dx, RootDirSectors
    add ax, dx
    add ax, SectorBalance
    add bx, [BPB_BytesPerSec]
    jmp Label_Go_On_Loading_File

Label_File_lLoaded:
    jmp $

;========== get FAT Entry
; 根据给定的FAT表项索引，在FAT表中查询链表中的下一个索引
; 输入：
;       ax = 给定的FAT表项索引
; 输出：
;       ax = 下一个FAT表项的索引
Func_GetFATEntry:
    push es
    push bx
    push ax

    mov ax, 0
    mov es, ax
    pop ax

    mov byte [Odd], 0
    mov bx, 3
    mul bx        ; dx:ax = ax * bx
    mov bx, 2
    div bx
    jz Label_Even
    mov byte [Odd], 1

Label_Even:
; 读取两个扇区的FAT表的内容到内存，用于一会儿的查询
    xor dx, dx
    mov bx, [BPB_BytesPerSec]
    div bx
    push dx
    mov bx, 0x8000
    add ax, SectorNumOfFATStart
    mov cl, 2
    call Func_ReadOneSector

    pop dx
    add bx, dx
    mov ax, [es:bx]
    cmp byte [Odd], 1
    jnz Label_Even_2
    shr ax, 4

Label_Even_2
    and ax, 0x0fff
    pop bx
    pop es
    ret

    hlt
BaseBootMessage   db 'Start Boot。。。。'
NoLoaderMessage   db 'There is not loader.bin'
FileFoundMessage  db 'Found the loader.bin'

Odd               db 0
SectorNo          dw 0
RootDirSizeForLoop dw RootDirSectors
LoaderFileName   db 'ROOT    BIN'
times 510 - ($ - $$) db 0
db 0x55, 0xaa

