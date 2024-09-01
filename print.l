#include <alef.h>

int
Addrconv(Printspec *p)
{
	byte buffer[16];
	uint addr;

	addr = *(uint *)p->o;
	snprint(buffer, sizeof buffer, "%d.%d.%d.%d", (addr & 0xFF), ((addr >> 8) & 0xFF), ((addr >> 16) & 0xFF), ((addr >> 24) & 0xFF));
	strconv(p, buffer);
	return sizeof(uint);
}
