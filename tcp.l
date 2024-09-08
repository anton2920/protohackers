#include <alef.h>
#include "hackers.h"


intern
usint
htons(usint port)
{
	return ((port & 0xFF) << 8) | (port >> 8);
}


int
TCPListen(uint addr, usint port, int backlog)
{
	SockaddrIn sin;
	int	ret, one;
	int	l;

	l = socket(PF_INET, SOCK_STREAM, 0);
	if (l < 0) {
		werrstr("failed to create new socket: %r");
		return - 1;
	}

	one = 1;
	ret = setsockopt(l, SOL_SOCKET, SO_REUSEADDR, (byte * ) & one, sizeof one);
	if (ret < 0) {
		werrstr("failed to set socket option: %r");
		return -1;
	}

	sin.family = AF_INET;
	sin.port = htons(port);
	sin.addr = addr;
	ret = _bind(l, (Sockaddr * ) & sin, sizeof sin);
	if (ret < 0) {
		werrstr("failed to bind socket to address: %r");
		return - 1;
	}

	ret = _listen(l, 128);
	if (ret < 0) {
		werrstr("failed to start listening on socket: %r");
		return - 1;
	}

	return l;
}


