#define ArrayLength(arr) sizeof(arr) / sizeof((arr)[0])


/* event.l */
enum Request {
	RequestRead = 1 << 0,
	RequestWrite = 1 << 1,
};

enum Trigger {
	TriggerLevel,
	TriggerEdge,
};

enum EventType {
	EventRead = EVFILT_READ,
	EventWrite = EVFILT_WRITE,
	EventSignal = EVFILT_SIGNAL,
};

aggr Event
{
	uint	Identifier;
	sint	Type;
	usint	Flags;
	uint	Fflags;
	uint	_;
	int	Data1;
	int	Data2;
	void	*UserData;
	uint	_[9];
};

adt EventQueue
{
	int kq;

	int	Init(*EventQueue);
	int	AddSocket(*EventQueue, int, Request, Trigger, void *);
	int	AddSignal(*EventQueue, int);
	int	GetEvents(*EventQueue, Event*, int);
	int	Close(*EventQueue);
};

/* log.l */
enum Level {
	LevelDebug,
	LevelInfo,
	LevelWarn,
	LevelError,
	LevelFatal
};

void	Logf(Level, byte*, void*);
void	Debugf(byte*, ...);
void	Infof(byte*, ...);
void	Warnf(byte*, ...);
void	Errorf(byte*, ...);
void	Fatalf(byte*, ...);
Level	SetLevel(Level);

/* print.l */
int	Addrconv(Printspec*);

/* signal.l */
int	IgnoreSignal(int);

/* tcp.l */
int	TCPListen(uint, usint, int);
