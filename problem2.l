#include <alef.h>
#include "hackers.h"

#define MessageLength 9


aggr ClientItems
{
	int	*Prices;
	int	*Times;
	int	Len;
	int	Cap;
};


aggr ClientData
{
	Circular Buffer;
	ClientItems Items;
};


int
ntohl(int n)
{
	byte bytes[sizeof(n)];
	byte * pn;
	int	i;

	pn = (byte * ) & n;
	for (i = 0; i < sizeof(n); i++) {
		bytes[i] = pn[sizeof(n)-i-1];
	}

	return * (int *)bytes;
}


intern
void
initClientData(ClientData *data)
{
	data->Buffer.Init(DefaultBufsize);

	data->Items.Len = 0;
	data->Items.Cap = 16;

	data->Items.Prices = malloc(data->Items.Cap * sizeof(data->Items.Prices[0]));
	check data->Items.Prices != nil, "failed to allocate prices";

	data->Items.Times = malloc(data->Items.Cap * sizeof(data->Items.Times[0]));
	check data->Items.Times != nil, "failed to allocate times";
}


intern
void
deinitClientData(ClientData *data)
{
	if (data != nil) {
		data->Buffer.Free();

		free(data->Items.Prices);
		free(data->Items.Times);
	}
}


intern
void
processInsertMessage(byte *buffer, ClientData *data)
{
	int	price;
	int	time;
	int	pos;

	time = ntohl(*(int *) & buffer[1]);
	price = ntohl(*(int *) & buffer[5]);

	pos = 0;
	while ((pos < data->Items.Len) && (time > data->Items.Times[pos])) {
		pos++;
	}
	if ((data->Items.Len > 0) && (time == data->Items.Times[pos])) {
		data->Items.Prices[pos] = price;
	} else {
		if (data->Items.Len == data->Items.Cap) {
			void * temp;

			temp = realloc(data->Items.Prices, data->Items.Cap * 2 * sizeof(data->Items.Prices[0]));
			check temp != nil, "failed to reallocate prices";
			data->Items.Prices = temp;

			temp = realloc(data->Items.Times, data->Items.Cap * 2 * sizeof(data->Items.Times[0]));
			check temp != nil, "failed to reallocate times";
			data->Items.Times = temp;

			data->Items.Cap *= 2;
		}

		ArrayInsertAt(data->Items.Prices, data->Items.Len, data->Items.Cap, price, pos);
		ArrayInsertAt(data->Items.Times, data->Items.Len, data->Items.Cap, time, pos);

		data->Items.Len++;
	}
}


intern
int
processQueryMessage(byte *buffer, ClientData *data)
{
	int	startPos, endPos, pos;
	int	startTime, endTime;

	float	sum;
	int	count;
	int	avg;

	startTime = ntohl(*(int *) & buffer[1]);
	endTime = ntohl(*(int *) & buffer[5]);

	startPos = data->Items.Len;
	for (pos = 0; pos < data->Items.Len; pos++) {
		if (startTime <= data->Items.Times[pos]) {
			startPos = pos;
			break;
		}
	}

	endPos = -1;
	for (pos = data->Items.Len - 1; pos >= startPos; pos--) {
		if (endTime >= data->Items.Times[pos]) {
			endPos = pos;
			break;
		}
	}

	sum = 0;
	count = 0;
	for (pos = startPos; pos <= endPos; pos++) {
		sum += data->Items.Prices[pos];
		count++;
	}

	avg = 0;
	if (count > 0) {
		avg = ntohl(sum / count);
	}

	Debugf("Avg for (%d, %d) = %g/%d = %d", startTime, endTime, sum, count, ntohl(avg));
	return avg;
}


intern
void
worker(EventQueue *q)
{
	byte * unconsumed;
	ClientData * data;
	int	nbytes;
	int	avg;

	ProcInit();

	while (1) {
		Circular * buffer;
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

			data = event->UserData;

			buffer = &data->Buffer;
			bytesRead = 0;
			while (bytesRead < event->Data[0]) {
				int	remainingSpace;
				remainingSpace = buffer->RemainingSpace();

				if (remainingSpace == 0) {
					Errorf("No space left in buffer");
					goto closeConnection;
				}

				nbytes = read(event->Identifier, buffer->Remaining(), remainingSpace);
				if (nbytes < 0) {
					Errorf("Failed to read data from client: %r");
					goto closeConnection;
				}
				bytesRead += nbytes;
				buffer->Produce(nbytes);

				while (buffer->UnconsumedLen() >= MessageLength) {
					unconsumed = buffer->Unconsumed();

					switch (unconsumed[0]) {
					case 'I':
						processInsertMessage(unconsumed, data);
						break;
					case 'Q':
						avg = processQueryMessage(unconsumed, data);

						nbytes = write(event->Identifier, &avg, sizeof(avg));
						if (nbytes < 0) {
							Warnf("Failed to write to client: %r");
						}

						break;
					}

					buffer->Consume(MessageLength);
				}
			}

			if (event->EndOfFile()) {
				goto closeConnection;
			}

			continue;
closeConnection:
			Debugf("Got disconnect from %d", event->Identifier);
			close(event->Identifier);
			deinitClientData(data);
			unalloc data;
		}
	}
}


void
Problem2(sint port)
{
	EventQueue qs[NWORKERS], q;
	ClientData * data;
	int	i, l, ret, rr;

	ProcInit();

	l = TCPListen(INADDR_ANY, port, 128);
	check l >= 0, "failed to listen on TCP socket";

	Infof("Listening on 0.0.0.0:%d...", port);

	for (i = 0; i < NWORKERS; ++i) {
		ret = qs[i].Init();
		check ret >= 0, "failed to initialize event queue for worker";
		proc worker(&qs[i]);
	}

	ret = q.Init();
	check ret >= 0, "failed to initialize event queue";

	ret = q.AddSocket(l, RequestRead, TriggerEdge, nil);
	check ret >= 0, "failed to add socket to event queue";

	rr = 0;
	while (1) {
		SockaddrIn addr;
		Event events[64];
		uint addrlen;
		int	c, n;

		n = q.GetEvents(events, ArrayLength(events));
		if (n < 0) {
			Errorf("Failed to get events from queue: %r");
			continue;
		}

		for (i = 0; i < n; ++i) {
			Event * event;
			event = &events[i];

			Debugf("[ main ]: Got event %E", event);

			addrlen = sizeof addr;
			c = _accept(l, (Sockaddr * ) & addr, &addrlen);
			if (c < 0) {
				Errorf("Failed to accept incoming connection: %r");
				continue;
			}

			Debugf("Accepted from %A:%d", addr.addr, addr.port);

			alloc data;
			initClientData(data);

			qs[rr++].AddSocket(c, RequestRead, TriggerEdge, data);
			rr %= NWORKERS;
		}
	}
}


