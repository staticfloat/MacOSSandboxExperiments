#include <stdio.h>
#include <errno.h>
#include <unistd.h>

int main() {
    int ret = access("/tmp/foo", X_OK);
    if (ret == -1) {
        printf("access() failed with: %d\n", errno);
    } else {
        printf("access() succeeded with: %d\n", ret);
    }
}
