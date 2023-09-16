/***************************************************
*		版权声明
*
*	本操作系统名为：MINE
*	该操作系统未经授权不得以盈利或非盈利为目的进行开发，
*	只允许个人学习以及公开交流使用
*
*	代码最终所有权及解释权归田宇所有；
*
*	本模块作者：	田宇
*	EMail:		345538255@qq.com
*
*
***************************************************/
#include"printk.h"

void SetColor(int *addr, char r, char g, char b);

void Start_Kernel(void)
{
	Pos.XResolution = 1440;
	Pos.YResolution = 900;

	Pos.XPosition = 0;
	Pos.YPosition = 0;

	Pos.XCharSize = 8;
	Pos.YCharSize = 16;

	Pos.FB_addr = (int*)0xffff800000a00000;
	Pos.FB_length = (Pos.XResolution * Pos.YResolution * 4);

	int *addr = (int*)0xffff800000a00000;
	for(int i = 0; i < 1440 * 20; i ++) 
	{
		SetColor(addr, 0xff, 0, 0);
		addr += 1;
	}

	for(int i = 0; i < 1440 * 20; i ++) 
	{
		SetColor(addr, 0, 0xff, 0);
		addr += 1;
	}

	for(int i = 0; i < 1440 * 20; i ++) 
	{
		SetColor(addr, 0, 0, 0xff);
		addr += 1;
	}

	for(int i = 0; i < 1440 * 20; i ++) 
	{
		SetColor(addr, 0xff, 0xff, 0xff);
		addr += 1;
	}

	for(int i = 0; i < 1440 * 20; i ++) 
	{
		SetColor(addr, 0, 0, 0xff);
		addr += 1;
	}

	color_printk(WHITE, BLACK, "Hello World The new make file!\n");

	int i = 1 / 0;

	while(1)
		;
}

void SetColor(int *addr, char r, char g, char b) 
{
	*((char*)addr + 0) = b;
	*((char*)addr + 1) = g;
	*((char*)addr + 2) = r;
	*((char*)addr + 3) = 0;
}
