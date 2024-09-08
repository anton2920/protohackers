#define ArrayLength(arr) sizeof(arr) / sizeof((arr)[0])

enum bool {
	false,
	true,
};


/* circular.l */
adt Circular
{
	byte	*buf;
	int	len;

	int	head;
	int	tail;

	int	Init(*Circular, int);
	void	Consume(*Circular, int);
	void	Produce(*Circular, int);
	byte	 * Remaining(*Circular);
	int	RemainingSpace(*Circular);
	byte	 * Unconsumed(*Circular);
	int	UnconsumedLen(*Circular);
	void	Free(*Circular);
};


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

adt Event
{
	extern uint	Identifier;
	extern sint	Type;
	extern usint	Flags;
	extern uint	Fflags;
	extern int	Data[2];
	extern void	*UserData;
	extern uint	_[8];

	int	EndOfFile(*Event);
};


adt EventQueue
{
	int	kq;

	int	Init(*EventQueue);
	int	AddSocket(*EventQueue, int, Request, Trigger, void *);
	int	AddSignal(*EventQueue, int);
	int	GetEvents(*EventQueue, Event*, int);
	int	Close(*EventQueue);
};


int	Eventconv(Printspec*);

/* json.l */
typedef aggr JsonValue;

enum JsonValueType {
	JsonNone,
	JsonNull,
	JsonBoolean,
	JsonInteger,
	JsonReal,
	JsonString,
	JsonObj,
	JsonArr,
};

aggr JsonArray
{
	JsonValue *Values;
	int	Len;
	int	Cap;
};


aggr JsonObject
{
	byte * *Keys;
	JsonValue * Values;
	int	Len;
	int	Cap;
};


aggr JsonValue
{
	JsonValueType Type;
	union
	 {
		bool Boolean;
		int	Integer;
		float	Real;
		byte * String;
		JsonObject Object;
		JsonArray Array;
	};
};


aggr Json
{
	JsonValueType Type;
	union
	 {
		JsonObject Object;
		JsonArray Array;
	};
};


int	ParseJson(byte*, int, Json*);
void	FreeJson(Json*);
int	Jsonconv(Printspec*);

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
