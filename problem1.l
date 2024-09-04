#include <alef.h>
#include "hackers.h"


extern int	Pids[];
extern int	CurrentPid;
extern Lock	PidsLock;


intern
int
IsPrime(int x)
{
	int	i;

	if (x == 1) {
		return 0;
	} else if (x == 2) {
		return 1;
	}

	for (i = 3; i < (int) ceil(sqrt(x)); ++i) {
		if (x % i == 0) {
			return 0;
		}
	}

	return 1;
}


void
Problem1(EventQueue *q)
{
	int	bytesRead, bytesConsumed;
	int	nbytes, consumed;
	byte buffer[1024];
	Json json;

	PidsLock.lock();
	Pids[CurrentPid++] = getpid();
	PidsLock.unlock();

	while (1) {
		Event events[64];
		int	bytesRead;
		int	i, n;

		n = q->GetEvents(events, ArrayLength(events));
		if (n < 0) {
			/* TODO(anton2920): break only on EINVAl. */
			break;
		}

		for (i = 0; i < n; ++i) {
			Event * event;
			event = &events[i];

			Debugf("[worker]: Got event %E", event);

			if (event->Data[0] > 0) {
				switch (event->Type) {
				case EventRead:
					bytesRead = 0;
					while (bytesRead < event->Data[0]) {
						nbytes = read(event->Identifier, buffer, sizeof buffer);
						if (nbytes < 0) {
							Errorf("Failed to read from client: %r");
							continue 2;
						}
						bytesRead += nbytes;
					}

					bytesConsumed = 0;
					while (bytesConsumed < bytesRead) {
						consumed = ParseJson(buffer, nbytes, &json);
						if (consumed < 0) {
							Errorf("Failed to parse JSON: %r");
						}
						bytesConsumed += consumed;

						/* 2. If number is real -> not prime. */
						/* 3. Do primality test. */
						/* 4. Respond. */
						/* 5. GOTO 0. */
					}

					/* fallthrough. */
				case EventWrite:
					break;
				}
			}

			if (event->EndOfFile()) {
				close(event->Identifier);
				continue;
			}
		}
	}
}


