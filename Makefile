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

$(out)/system: $(out)/head.o $(out)/entry.o $(out)/trap.o $(out)/main.o $(out)/printk.o $(out)/memory.o
	ld -b elf64-x86-64 -z muldefs -o $(out)/system $(out)/head.o $(out)/entry.o $(out)/trap.o $(out)/main.o $(out)/printk.o $(out)/memory.o -T Kernel.lds 

$(out)/main.o: $(source)/main.c
	gcc -fno-stack-protector -mcmodel=large -fno-builtin -m64 -c $(source)/main.c -I $(inc) -o $(out)/main.o

$(out)/head.o: $(source)/head.S
	gcc -fno-stack-protector -E $(source)/head.S > $(out)/_head.s
	as --64 -o $(out)/head.o $(out)/_head.s

$(out)/entry.o: $(source)/entry.S
	gcc -E  $(source)/entry.S > $(out)/entry.s -I $(inc)
	as --64 -o $(out)/entry.o $(out)/entry.s 

$(out)/trap.o: $(source)/trap.c
	gcc -mcmodel=large -fno-builtin -m64 -fno-stack-protector -c $(source)/trap.c -I $(inc) -o $(out)/trap.o 

$(out)/printk.o: $(source)/printk.c
	gcc -mcmodel=large -fno-builtin -m64 -c $(source)/printk.c -fno-stack-protector -I $(inc) -o $(out)/printk.o 

$(out)/memory.o: $(source)/memory.c
	gcc -mcmodel=large -fno-builtin -m64 -c $(source)/memory.c -fno-stack-protector -I $(inc) -o $(out)/memory.o 

clean:
	rm -rf *.o *.s~ *.s *.S~ *.c~ *.h~ system  Makefile~ Kernel.lds~ kernel.bin 

