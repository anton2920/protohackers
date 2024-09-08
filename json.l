#include <alef.h>
#include "hackers.h"

#define isspace(c) ((c == ' ') || (c == '\t') || (c == '\n') || (c == '\v'))
#define DefaultCapacity 16


enum JsonTokenType {
	JsonTokenNone,
	JsonTokenLbrace,
	JsonTokenRbrace,
	JsonTokenLbracket,
	JsonTokenRbracket,
	JsonTokenColon,
	JsonTokenComma,
	JsonTokenNull,
	JsonTokenFalse,
	JsonTokenTrue,
	JsonTokenNumber,
	JsonTokenString,
};

aggr JsonToken
{
	JsonTokenType Type;
	int	Pos;
	int	Len;
	union
	 {
		float	Number;
		byte * String;
	};
};


aggr JsonTokens
{
	JsonToken * Tokens;
	int	Len;
	int	Cap;
};


intern int	parseJsonValue(JsonTokens*, int, JsonValue*);

intern void	freeJsonObject(JsonObject*);
intern void	freeJsonArray(JsonArray*);
intern void	freeJsonValue(JsonValue*);

intern void	printJsonValue(Printspec*, JsonValue*);


intern
int
tokenizeJson(byte *data, int size, JsonTokens *tokens)
{
	int	pos, offset, ntokens;
	byte * end, *endptr;
	JsonToken * token;
	float	num;

	tokens->Len = 0;
	tokens->Cap = DefaultCapacity;
	tokens->Tokens = malloc(tokens->Cap * sizeof(tokens->Tokens[0]));
	rescue {
		free(tokens->Tokens);
		return - 1;
	}
	check tokens->Tokens != nil, "failed to allocate tokens array";

	pos = 0;
	while (pos < size) {
		while (isspace(data[pos])) {
			++pos;
			continue;
		}

		token = &tokens->Tokens[tokens->Len];
		token->Pos = pos;

		switch data[pos] {
		case '{':
			token->Type = JsonTokenLbrace;
			++pos;
			break;
		case '}':
			token->Type = JsonTokenRbrace;
			++pos;
			break;
		case '[':
			token->Type = JsonTokenLbracket;
			++pos;
			break;
		case ']':
			token->Type = JsonTokenRbracket;
			++pos;
			break;
		case ':':
			token->Type = JsonTokenColon;
			++pos;
			break;
		case ',':
			token->Type = JsonTokenComma;
			++pos;
			break;
		case 'n':
			if (pos + 3 >= size) {
				werrstr("malformed null at pos %d", pos);
				raise;
			}
			token->Type = JsonTokenNull;
			pos += 4;
			break;
		case 'f':
			if (pos + 4 >= size) {
				werrstr("malformed false at pos %d", pos);
				raise;
			}
			token->Type = JsonTokenFalse;
			pos += 5;
			break;
		case 't':
			if (pos + 3 >= size) {
				werrstr("malformed true at pos %d", pos);
				raise;
			}
			token->Type = JsonTokenTrue;
			pos += 4;
			break;
		case '"':
			offset = 0;
			while (1) {
				end = strchr(&data[pos+offset+1], '"');
				if (end == nil) {
					werrstr("malformed string at pos %d", pos);
					raise;
				}
				if (*(end-1) != '\\') {
					break;
				}
				offset = end - &data[pos+1] + 1;
			}

			token->Type = JsonTokenString;
			token->String = &data[pos+1];
			token->Len = end - &data[pos+1];
			pos += token->Len + 2;
			break;
		default:
			num = strtof(&data[pos], &endptr);
			if ((*endptr != ',') && (*endptr != '}') && (*endptr != ']') && (!isspace(*endptr))) {
				werrstr("invaild token '%c' at pos %d", data[pos], pos);
				raise;
			}

			token->Type = JsonTokenNumber;
			token->Number = num;
			pos += endptr - &data[pos];
		}

		if (++tokens->Len > tokens->Cap) {
			tokens->Cap *= 2;
			tokens->Tokens = realloc(tokens->Tokens, tokens->Cap * sizeof(JsonToken));
			check tokens->Tokens != nil, "failed to reallocate tokens array";
		}
	}

	return pos;
}


intern
byte *
makeCString(byte *buffer, int size)
{
	byte * ret;

	ret = malloc(size + 1);
	check ret != nil, "failed to allocate buffer for C string";

	memcpy(ret, buffer, size);
	return ret;
}


intern
int
parseJsonColon(JsonTokens *tokens, int start)
{
	JsonToken * token;

	if (start >= tokens->Len) {
		werrstr("expected colon, got EOF");
		return - 1;
	}

	token = &tokens->Tokens[start];
	if (token->Type != JsonTokenColon) {
		werrstr("expected colon, got %d", token->Type);
		return - 1;
	}

	return 1;
}


intern
int
parseJsonComma(JsonTokens *tokens, int start)
{
	JsonToken * token;

	if (start >= tokens->Len) {
		werrstr("expected comma, got EOF");
		return - 1;
	}

	token = &tokens->Tokens[start];
	if (token->Type != JsonTokenComma) {
		werrstr("expected comma, got %d at pos %d", token->Type, token->Pos);
		return - 1;
	}

	return 1;
}


intern
int
parseJsonRbrace(JsonTokens *tokens, int start)
{
	JsonToken * token;

	if (start >= tokens->Len) {
		werrstr("expected }, got EOF");
		return - 1;
	}

	token = &tokens->Tokens[start];
	if (token->Type != JsonTokenRbrace) {
		werrstr("expected }, got %d, at pos %d", token->Type, token->Pos);
		return - 1;
	}

	return 1;
}


intern
int
parseJsonRbracket(JsonTokens *tokens, int start)
{
	JsonToken * token;

	if (start >= tokens->Len) {
		werrstr("expected }, got EOF");
		return - 1;
	}

	token = &tokens->Tokens[start];
	if (token->Type != JsonTokenRbracket) {
		werrstr("expected ], got %d at pos %d", token->Type, token->Pos);
		return - 1;
	}

	return 1;
}


intern
int
parseJsonKey(JsonTokens *tokens, int start, byte **key)
{
	JsonToken * token;

	if (start >= tokens->Len) {
		werrstr("expected key, got EOF");
		return - 1;
	}

	token = &tokens->Tokens[start];
	if (token->Type != JsonTokenString) {
		werrstr("JSON key must be a string");
		return - 1;
	}
	*key = makeCString(token->String, token->Len);

	return 1;
}


intern
int
parseJsonObject(JsonTokens *tokens, int start, JsonObject *object)
{
	JsonToken * token;
	int	pos, ret;

	if (start >= tokens->Len) {
		werrstr("expected object, got EOF");
		return - 1;
	}

	object->Len = 0;
	object->Cap = 0;
	ret = parseJsonRbrace(tokens, start);
	if (ret > 0) {
		return 1;
	}

	object->Cap = DefaultCapacity;
	object->Keys = malloc(object->Cap * sizeof(object->Keys[0]));
	object->Values = malloc(object->Cap * sizeof(object->Values[0]));
	rescue {
		freeJsonObject(object);
		return - 1;
	}
	check object->Keys != nil, "failed to allocate JSON keys array";
	check object->Values != nil, "failed to allocate JSON values array";

	pos = start;
	while (pos  < tokens->Len - 1) {
		token = &tokens->Tokens[pos];

		if (pos - start > 0) {
			ret = parseJsonRbrace(tokens, pos);
			if (ret > 0) {
				return pos + ret - start;
			}

			ret = parseJsonComma(tokens, pos);
			if (ret < 0) {
				werrstr("failed to parse comma: %r");
				raise;
			}
			pos += ret;
		}

		ret = parseJsonKey(tokens, pos, &object->Keys[object->Len]);
		if (ret < 0) {
			werrstr("failed to parse JSON object key: %r");
			raise;
		}
		pos += ret;

		/* TODO(anton2920): free key string on error. */

		ret = parseJsonColon(tokens, pos);
		if (ret < 0) {
			werrstr("failed to parse JSON colon: %r");
			raise;
		}
		pos += ret;

		ret = parseJsonValue(tokens, pos, &object->Values[object->Len]);
		if (ret < 0) {
			werrstr("failed to parse JSON object value: %r");
			raise;
		}
		pos += ret;

		if (++object->Len > object->Cap) {
			object->Cap *= 2;
			object->Keys = realloc(object->Keys, object->Cap * sizeof(object->Keys[0]));
			object->Values = realloc(object->Values, object->Cap * sizeof(object->Values[0]));
			check object->Keys != nil, "failed to reallocate JSON object keys array";
			check object->Values != nil, "failed to reallocate JSON object values array";
		}
	}

	ret = parseJsonRbrace(tokens, pos);
	if (ret < 0) {
		werrstr("failed to parse '}': %r");
		raise;
	}
	pos += ret;

	return pos - start;
}


intern
int
parseJsonArray(JsonTokens *tokens, int start, JsonArray *array)
{
	JsonToken * token;
	int	pos, ret;

	if (start >= tokens->Len) {
		werrstr("expected array, got EOF");
		return - 1;
	}

	array->Len = 0;
	array->Cap = 0;
	ret = parseJsonRbracket(tokens, start);
	if (ret > 0) {
		return 1;
	}

	array->Cap = DefaultCapacity;
	array->Values = malloc(array->Cap * sizeof(array->Values[0]));
	rescue {
		freeJsonArray(array);
		return - 1;
	}
	check array->Values != nil, "failed to allocate JSON values array";

	pos = start;
	while (pos < tokens->Len - 1) {
		token = &tokens->Tokens[pos];

		if (pos - start > 0) {
			ret = parseJsonRbracket(tokens, pos);
			if (ret > 0) {
				return pos + ret - start;
			}

			ret = parseJsonComma(tokens, pos);
			if (ret < 0) {
				werrstr("failed to parse comma: %r");
				raise;
			}
			pos += ret;
		}

		ret = parseJsonValue(tokens, pos, &array->Values[array->Len]);
		if (ret < 0) {
			werrstr("failed to parse JSON value: %r");
			raise;
		}
		pos += ret;

		if (++array->Len > array->Cap) {
			array->Cap *= 2;
			array->Values = realloc(array->Values, array->Cap * sizeof(array->Values[0]));
			check array->Values != nil, "failed to reallocate JSON array values array";
		}
	}

	ret = parseJsonRbracket(tokens, pos);
	if (ret < 0) {
		werrstr("failed to parse ']': %r");
		raise;
	}
	pos += ret;

	return pos - start;
}


intern
int
parseJsonValue(JsonTokens *tokens, int start, JsonValue *value)
{
	int	ret, consumed;
	JsonToken * token;

	if (start >= tokens->Len) {
		werrstr("expected value, got EOF");
		return - 1;
	}

	consumed = 1;
	ret = 0;

	token = &tokens->Tokens[start];
	switch token->Type {
	case JsonTokenNull:
		value->Type = JsonNull;
		break;
	case JsonTokenFalse:
		value->Type = JsonBoolean;
		value->Boolean = false;
		break;
	case JsonTokenTrue:
		value->Type = JsonBoolean;
		value->Boolean = true;
		break;
	case JsonTokenNumber:
		if (ceil(token->Number) - floor(token->Number) < 1e-9) {
			value->Type = JsonInteger;
			value->Integer = (int) token->Number;
		} else {
			value->Type = JsonReal;
			value->Real = token->Number;
		}
		break;
	case JsonTokenString:
		value->Type = JsonString;
		value->String = makeCString(token->String, token->Len);
		break;
	case JsonTokenLbrace:
		value->Type = JsonObj;
		ret = parseJsonObject(tokens, start + 1, &value->Object);
		break;
	case JsonTokenLbracket:
		value->Type = JsonArr;
		ret = parseJsonArray(tokens, start + 1, &value->Array);
		break;
	default:
		werrstr("expected JSON value, got %d", token->Type);
		return - 1;
	}
	if (ret < 0) {
		werrstr("failed to parse JSON value: %r");
		return - 1;
	}
	consumed += ret;

	return consumed;
}


int
ParseJson(byte *data, int size, Json *json)
{
	JsonTokens tokens;
	JsonToken * token;
	int	consumed;
	int	ntokens;

	consumed = tokenizeJson(data, size, &tokens);
	if (consumed < 0) {
		werrstr("failed to tokenize JSON: %r");
		return - 1;
	}

	token = &tokens.Tokens[0];
	switch token->Type {
	case JsonTokenLbrace:
		json->Type = JsonObj;
		ntokens = parseJsonObject(&tokens, 1, &json->Object);
		break;
	case JsonTokenLbracket:
		json->Type = JsonArr;
		ntokens = parseJsonArray(&tokens, 1, &json->Array);
		break;
	default:
		werrstr("expected JSON array or object, got %d", token->Type);
		return - 1;
	}
	if (ntokens < 0) {
		return - 1;
	}

	free(tokens.Tokens);
	return consumed;
}


intern
void
freeJsonObject(JsonObject *object)
{
	int	i;

	for (i = 0; i < object->Len; ++i) {
		free(object->Keys[i]);
		freeJsonValue(&object->Values[i]);
	}
	free(object->Keys);
	free(object->Values);
}


intern
void
freeJsonArray(JsonArray *array)
{
	int	i;

	for (i = 0; i < array->Len; ++i) {
		freeJsonValue(&array->Values[i]);
	}
	free(array->Values);
}


intern
void
freeJsonValue(JsonValue *value)
{
	switch value->Type {
	case JsonString:
		free(value->String);
		break;
	case JsonObj:
		freeJsonObject(&value->Object);
		break;
	case JsonArr:
		freeJsonArray(&value->Array);
		break;
	}
}


void
FreeJson(Json *json)
{
	switch (json->Type) {
	case JsonObj:
		freeJsonObject(&json->Object);
		break;
	case JsonArr:
		freeJsonArray(&json->Array);
		break;
	}
}


intern
void
printJsonObject(Printspec *p, JsonObject *object)
{
	int	i;

	strconv(p, "{ ");
	for (i = 0; i < object->Len; ++i) {
		if (i > 0) {
			strconv(p, ", ");
		}
		strconv(p, "\"");
		strconv(p, object->Keys[i]);
		strconv(p, "\": ");
		printJsonValue(p, &object->Values[i]);
	}
	strconv(p, " }");
}


intern
void
printJsonArray(Printspec *p, JsonArray *array)
{
	int	i;

	strconv(p, "[ ");
	for (i = 0; i < array->Len; ++i) {
		if (i > 0) {
			strconv(p, ", ");
		}
		printJsonValue(p, &array->Values[i]);
	}
	strconv(p, " ]");
}


intern
void
printJsonValue(Printspec *p, JsonValue *value)
{
	byte buffer[128];

	switch (value->Type) {
	case JsonNull:
		strconv(p, "null");
		break;
	case JsonBoolean:
		if (!value->Boolean) {
			strconv(p, "false");
		} else {
			strconv(p, "true");
		}
		break;
	case JsonInteger:
		snprint(buffer, sizeof buffer, "%d", value->Integer);
		strconv(p, buffer);
		break;
	case JsonReal:
		snprint(buffer, sizeof buffer, "%g", value->Real);
		strconv(p, buffer);
		break;
	case JsonString:
		strconv(p, "\"");
		strconv(p, value->String);
		strconv(p, "\"");
		break;
	case JsonObj:
		printJsonObject(p, &value->Object);
		break;
	case JsonArr:
		printJsonArray(p, &value->Array);
		break;
	}
}


int
Jsonconv(Printspec *p)
{
	Json * json;

	json = (Json * )p->o;
	switch (json->Type) {
	case JsonObj:
		printJsonObject(p, &json->Object);
		break;
	case JsonArr:
		printJsonArray(p, &json->Array);
		break;
	}

	return sizeof(Json);
}


