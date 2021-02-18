#include <stdio.h>

int main() {
   printf("Running...\n");
   *(int*)0 = 0;
   return 0;
}
