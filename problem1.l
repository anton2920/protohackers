#include <alef.h>
#include "hackers.h"


#define BatchSize 64


extern int	Pids[];
extern int	CurrentPid;
extern Lock	PidsLock;


intern
int
IsPrime(int x)
{
	int	i;

	if (x <= 1) {
		return 0;
	} else if (x == 2) {
		return 1;
	} else if ((x & 1) == 0) {
		return 0;
	}

	for (i = 3; i < (int) ceil(sqrt(x)); ++i) {
		if (x % i == 0) {
			return 0;
		}
	}

	return 1;
}


int
ParseRequest(Circular *buffer, Json *jsons, bool *valids, int njsons)
{
	int	unconsumedLen;
	byte * unconsumed;
	int	jsonSize;
	int	i, j;

	for (i = 0; i < njsons; ++i) {
		unconsumedLen = buffer->UnconsumedLen();
		if (unconsumedLen == 0) {
			break;
		}
		unconsumed = buffer->Unconsumed();

		Debugf("Unconsumed len = %d", unconsumedLen);

		jsonSize = -1;
		for (j = 0; j < unconsumedLen; ++j) {
			if (unconsumed[j] == '\n') {
				jsonSize = j;
				break;
			}
		}
		if (jsonSize < 0) {
			break;
		}
		Debugf("JSON size = %d", jsonSize);

		valids[i] = ParseJson(unconsumed, jsonSize, &jsons[i]) > 0;
		buffer->Consume(jsonSize + 1);
	}

	return i;
}


bool
ProduceResponse(byte *response, int size, Json *json, bool valid)
{
	int	i;

	if ((valid) && (json->Type == JsonObj)) {
		int	methodPos, numberPos;
		JsonValue * method, *number;

		methodPos = -1;
		numberPos = -1;
		for (i = 0; i < json->Object.Len; ++i) {
			if (strcmp(json->Object.Keys[i], "method") == 0) {
				methodPos = i;
			} else if (strcmp(json->Object.Keys[i], "number") == 0) {
				numberPos = i;
			}
		}

		if ((methodPos != -1) && (numberPos != -1)) {
			method = &json->Object.Values[methodPos];
			if ((method->Type == JsonString) && (strcmp(method->String, "isPrime") == 0)) {
				number = &json->Object.Values[numberPos];
				if ((number->Type == JsonInteger) || (number->Type == JsonReal)) {
					bool isPrime;

					switch number->Type {
					case JsonInteger:
						Debugf("Number (int) = %d", number->Integer);
						isPrime = IsPrime(number->Integer);
						break;
					case JsonReal:
						Debugf("Number (float) = %g", number->Real);
						isPrime = false;
						break;
					}

					if (isPrime) {
						strncpy(response, "{\"method\":\"isPrime\",\"prime\":true}\n", size);
					} else {
						strncpy(response, "{\"method\":\"isPrime\",\"prime\":false}\n", size);
					}

					return true;
				}
			}
		}
	}

	strncpy(response, "{\"error\": \"ERROR\"}", size);
	return false;
}


void
Problem1(EventQueue *q)
{
	int	nbytes, njsons, bytesRead;
	bool valids[BatchSize];
	Json jsons[BatchSize];
	byte response[128];
	bool ok;

	PidsLock.lock();
	Pids[CurrentPid++] = getpid();
	PidsLock.unlock();

	while (1) {
		Circular * buffer;
		Event events[1];
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

			buffer = event->UserData;
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
				Debugf("Payload = '%.*s'", buffer->UnconsumedLen(), buffer->Unconsumed());

				while (true) {
					njsons = ParseRequest(buffer, jsons, valids, BatchSize);
					Debugf("Got %d jsons", njsons);
					if (njsons == 0) {
						break;
					}

					for (i = 0; i < njsons; ++i) {
						ok = ProduceResponse(response, sizeof response, &jsons[i], valids[i]);
						if (write(event->Identifier, response, strlen(response)) < 0) {
							Errorf("Failed to write data to client: %r");
							goto closeConnection;
						}
						Debugf("Response = '%s' (%d)", response, ok);
						if (!ok) {
							goto closeConnection;
						}
					}
				}
			}

			if (event->EndOfFile()) {
				goto closeConnection;
			}

			continue;
closeConnection:
			close(event->Identifier);
			buffer->Free();
			unalloc buffer;
		}
	}
}


