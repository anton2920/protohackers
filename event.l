#include <alef.h>
#include "hackers.h"


intern
byte *EventType2String[] =
{
	[-EventRead] "Read",
	[-EventWrite] "Write",
	[-EventSignal] "Signal",
};


int
Event.EndOfFile(Event *e)
{
	return (e->Flags & EV_EOF) == EV_EOF;
}


int
EventQueue.Init(EventQueue *q)
{
	q->kq = kqueue();
	if (q->kq < 0) {
		werrstr("failed to create new kernel queue: %r");
		return - 1;
	}
	return 0;
}


int
EventQueue.AddSignal(EventQueue *q, int signal)
{
	Event event;
	int	ret;

	event.Identifier = signal;
	event.Type = EventSignal;
	event.Flags = EV_ADD;
	event.Fflags = 0;
	event.UserData = nil;

	ret = kevent(q->kq, (Kevent * ) & event, 1, nil, 0, nil);
	if (ret < 0) {
		werrstr("failed to request signal event: %r");
		return - 1;
	}
}


int
EventQueue.AddSocket(EventQueue *q, int sock, Request request, Trigger trigger, void *userData)
{
	usint flags;

	flags = EV_ADD;
	if (trigger == TriggerEdge) {
		flags |= EV_CLEAR;
	}

	if ((request & RequestRead) == RequestRead) {
		Event event;
		int	ret;

		memset(&event, 0, sizeof event);
		event.Identifier = sock;
		event.Type = EventRead;
		event.Flags = flags;
		event.UserData = userData;

		ret = kevent(q->kq, (Kevent * ) & event, 1, nil, 0, nil);
		if (ret < 0) {
			werrstr("failed to request read event for socket: %r");
			return - 1;
		}
	}

	if ((request & RequestWrite) == RequestWrite) {
		Event event;
		int	ret;

		memset(&event, 0, sizeof event);
		event.Identifier = sock;
		event.Type = EventWrite;
		event.Flags = flags;
		event.UserData = userData;

		ret = kevent(q->kq, (Kevent * ) & event, 1, nil, 0, nil);
		if (ret < 0) {
			werrstr("failed to request write event for socket: %r");
			return - 1;
		}
	}

	return 0;
}


int
EventQueue.GetEvents(EventQueue *q, Event *events, int nevents)
{
	int	n;

	n = kevent(q->kq, nil, 0, (Kevent * )events, nevents, nil);
	if (n < 0) {
		/* TODO(anton2920): handle EINTR. */
		return - 1;
	}
	return n;
}


int
EventQueue.Close(EventQueue *q)
{
	return close(q->kq);
}


int
Eventconv(Printspec *p)
{
	byte buffer[128];
	Event * event;

	event = *(Event * *)p->o;
	snprint(buffer, sizeof buffer, "{ID = %d, Type = %s, Data = %d, EOF = %d, UserData = %#uX}", event->Identifier, EventType2String[-event->Type], event->Data[0], event->EndOfFile(), event->UserData);
	strconv(p, buffer);

	return sizeof(Event * );
}


