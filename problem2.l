#include <alef.h>
#include "hackers.h"

#define MSG_LEN 9

extern int	Pids[];
extern int	CurrentPid;
extern Lock	PidsLock;

int
ntohl(int n)
{
	int res;
	res = ((n & 0x000000FF) << 24) | ((n & 0x0000FF00) << 8) | ((n & 0x00FF0000) >> 8) | ((n & 0xFF000000) >> 24);
	/* Debugf("Was: 0x%.4X, got: 0x%.4X", n, res); */
	return res;
}

void
InitClientData2(ClientData2 *data)
{
	data->Buffer.Init(DefaultBufsize);

	data->Items.Len = 0;
	data->Items.Cap = 1024;

	data->Items.Prices = malloc(data->Items.Cap * sizeof(data->Items.Prices));
	check data->Items.Prices != nil, "failed to allocate prices";

	data->Items.Times = malloc(data->Items.Cap * sizeof(data->Items.Times));
	check data->Items.Times != nil, "failed to allocate times";
}

void
DeinitClientData2(ClientData2 *data)
{
	data->Buffer.Free();

	// free(data->Items.Prices);
	// free(data->Items.Times);
}

void
Problem2(EventQueue *q)
{
	ClientData2 *data2;
	int	nbytes;

	PidsLock.lock();
	Pids[CurrentPid++] = getpid();
	PidsLock.unlock();

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

			data2 = event->UserData;

			buffer = &data2->Buffer;
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

				while (buffer->UnconsumedLen() >= MSG_LEN) {
					byte *data;
					data = buffer->Unconsumed();

					Debugf("Got message type '%c'", data[0]);

					switch (data[0]) {
					case 'I': {
						int price;
						int time;
						int pos;

						time = ntohl(*(int *)&data[1]);
						price = ntohl(*(int *)&data[5]);

						pos = 0;
						while ((pos < data2->Items.Len) && ((uint)time > (uint)data2->Items.Times[pos])) {
							pos++;
						}
						if (time == data2->Items.Times[pos]) {
							data2->Items.Prices[pos] = price;

							Debugf("Changed (%d, %d)", time, price);
						} else {
							if (data2->Items.Len == data2->Items.Cap) {
								void *temp;

								temp = realloc(data2->Items.Prices, data2->Items.Cap*2);
								check temp != nil, "failed to reallocate prices";
								data2->Items.Prices = temp;

								temp = realloc(data2->Items.Times, data2->Items.Cap*2);
								check temp != nil, "failed to reallocate times";
								data2->Items.Times = temp;

								data2->Items.Cap *= 2;
							}

							ArrayInsertAt(data2->Items.Prices, data2->Items.Len, data2->Items.Cap, price, pos);
							ArrayInsertAt(data2->Items.Times, data2->Items.Len, data2->Items.Cap, time, pos);

							data2->Items.Len++;

							Debugf("Added (%d, %d)", time, price);
						}
						break;
					}
					case 'Q': {
						int startTime, endTime;
						int startPos, endPos;
						int pos;
						int sum, count;
						int avg;

						startTime = ntohl(*(int*)&data[1]);
						endTime = ntohl(*(int*)&data[5]);

						startPos = 0;
						for (pos = 0; pos < data2->Items.Len; pos++) {
							if ((uint)startTime <= (uint)data2->Items.Times[pos]) {
								startPos = pos;
								break;
							}
						}

						endPos = data2->Items.Len-1;
						for (pos = data2->Items.Len-1; pos >= startPos; pos--) {
							if ((uint)endTime >= (uint)data2->Items.Times[pos]) {
								endPos = pos;
								break;
							}
						}

						ArrayPrint(data2->Items.Times, data2->Items.Len);
						Debugf("startPos = %d, endPos = %d", startPos, endPos);

						sum = 0;
						count = 0;
						for (pos = startPos; pos <= endPos; pos++) {
							sum += data2->Items.Prices[pos];
							count++;
						}

						if (count == 0) {
							avg = 0;
						} else {
							avg = ntohl(sum / count);
						}

						nbytes = write(event->Identifier, &avg, sizeof(avg));
						if (nbytes < 0) {
							Warnf("Failed to write to client: %r");
						}

						Debugf("Avg for (%d, %d) = %d", startTime, endTime, sum / count);
						break;
					}
					}

					buffer->Consume(MSG_LEN);
				}
			}

			if (event->EndOfFile()) {
				goto closeConnection;
			}

			continue;
		closeConnection:
			Debugf("Got disconnect from %d", event->Identifier);
			close(event->Identifier);
			DeinitClientData2(data2);
		}
	}
}