#include <alef.h>
#include "hackers.h"

#define PageSize 4096


intern byte	*currentBase = (void *)
0xA0000000;
intern Lock	baseLock;


intern
int
alignUp(int x, int quantum)
{
	return (x + (quantum - 1)) & ~(quantum - 1);
}


int
Circular.Init(Circular *c, int size)
{
	void * buffer, *ret;
	int	fd;

	size = alignUp(size, PageSize);

	fd = shm_open2(SHM_ANON, ORDWR, 0, 0, nil);
	rescue {
		close(fd);
		return - 1;
	}
	if (fd < 0) {
		werrstr("failed to open anonymous shared memory: %r");
		raise;
	}

	if (ftruncate(fd, size) < 0) {
		werrstr("failed to resize shared memory object: %r");
		raise;
	}

	baseLock.lock();
	currentBase += 2 * size;
	baseLock.unlock();
	buffer = mmap(currentBase, 2 * size, PROT_NONE, MAP_PRIVATE | MAP_ANON | MAP_FIXED, -1, 0);
	rescue {
		munmap(buffer, 2 * size);
		raise;
	}
	if (buffer == MAP_FAILED) {
		werrstr("failed to create initial memory mapping: %r");
		raise;
	}

	ret = mmap(buffer, size, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, fd, 0);
	if (ret == MAP_FAILED) {
		werrstr("failed to map first half of circular buffer: %r");
		raise;
	}
	ret = mmap((byte * )buffer + size, size, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, fd, 0);
	if (ret == MAP_FAILED) {
		werrstr("failed to map second half of circular buffer: %r");
		raise;
	}
	c->buf = buffer;
	c->len = size;

	/* NOTE(anton2920): sanity checks. */
	c->buf[0] = '\0';
	c->buf[size-1] = '\0';
	c->buf[size] = '\0';
	c->buf[2*size-1] = '\0';

	close(fd);
	return 0;
}


void
Circular.Consume(Circular *c, int n)
{
	c->head += n;
	if (c->head > c->len) {
		c->head -= c->len;
		c->tail -= c->len;
	}
}


void
Circular.Produce(Circular *c, int n)
{
	c->tail += n;
}


byte	*
Circular.Remaining(Circular *c)
{
	return & c->buf[c->tail];
}


int
Circular.RemainingSpace(Circular *c)
{
	return c->len - (c->tail - c->head);
}


byte	*
Circular.Unconsumed(Circular *c)
{
	return & c->buf[c->head];
}


int
Circular.UnconsumedLen(Circular *c)
{
	return c->tail - c->head;
}


void
Circular.Free(Circular *c)
{
	munmap(c->buf, 2 * c->len);
}


