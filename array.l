#include <alef.h>
#include "hackers.h"

int
ArrayInsertAt(int *array, int len, int cap, int value, int pos)
{
	check len + 1 <= cap, "no space left in array";
	check (pos >= 0) && (pos <= len), "invalid position to insert at";

	memmove(&array[pos+1], &array[pos], (len - pos) * sizeof(array[0]));
	array[pos] = value;

	return len + 1;
}


int
ArrayFind(int *array, int len, int value)
{
	int	i;

	for (i = 0; i < len; i++) {
		if (value == array[i]) {
			return i;
		}
	}

	return - 1;
}


void
ArrayPrint(int *array, int n)
{
	int	i;

	for (i = 0; i < n; i++) {
		if (i > 0) {
			print(", ");
		}
		print("%d", array[i]);
	}
	print("\n");
}


