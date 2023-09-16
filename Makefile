#/***************************************************
#		版权声明
#
#	本操作系统名为：MINE
#	该操作系统未经授权不得以盈利或非盈利为目的进行开发，
#	只允许个人学习以及公开交流使用
#
#	代码最终所有权及解释权归田宇所有；
#
#	本模块作者：	田宇
#	EMail:		345538255@qq.com
#
#
#***************************************************/
out = ./output
source = ./kernel/source
inc = ./kernel/include

all: $(out)/system
	objcopy -I elf64-x86-64 -S -R ".eh_frame" -R ".comment" -O binary $(out)/system $(out)/kernel.bin

$(out)/system:	$(out)/head.o $(out)/main.o $(out)/printk.o
	ld -b elf64-x86-64 -z muldefs -o $(out)/system $(out)/head.o $(out)/main.o $(out)/printk.o -T Kernel.lds 

$(out)/main.o:	$(source)/main.c
	gcc -fno-stack-protector -mcmodel=large -fno-builtin -m64 -c $(source)/main.c -I $(inc) -o $(out)/main.o

$(out)/head.o:	$(source)/head.S
	gcc -fno-stack-protector -E $(source)/head.S > $(out)/_head.s
	as --64 -o $(out)/head.o $(out)/_head.s

$(out)/printk.o: $(source)/printk.c
	gcc -mcmodel=large -fno-builtin -m64 -c $(source)/printk.c -fno-stack-protector -o $(out)/printk.o -I $(inc)

clean:
	rm -rf *.o *.s~ *.s *.S~ *.c~ *.h~ system  Makefile~ Kernel.lds~ kernel.bin 

