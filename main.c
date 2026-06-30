#include <sys/stat.h>
#include <libgen.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <unistd.h>
#include <limits.h>
#include <errno.h>

#include "api.h"

#define MAX_OPS 1000000
#define MAX_LINE_LEN 1024

// Command structure
struct command {
    char operation[10];
    int pageNumber;
    int startOffset;
    int value;
};

bool read_next_op(FILE *fp, struct command *op);
void mm_print_stats(FILE *fp, struct mm_stats *stats);

// Main function
// Read input file and call read/write accordingly
int main(int argc, char *argv[]) {
    printf("%s: Hello Memory Manager Project!\n", __func__);
    if (argc != 4) {
        fprintf(stderr, "Not enough parameters provided.  Usage: %s <replacement_policy> <num_frames> <input_file>\n", argv[0]);
        fprintf(stderr, "  Page replacement policy: 1 - FIFO\n");
        fprintf(stderr, "  Page replacement policy: 2 - Third Chance\n");
        return -1;
    }

    // Verify input
    int policy = atoi(argv[1]);
    if (policy != MM_FIFO && policy != MM_THIRD) {
        fprintf(stderr, "Invalid option\n");
        return -1;
    }
    int num_frames = atoi(argv[2]);
    if (num_frames <= 0) {
        fprintf(stderr, "Invalid number of frames\n");
        return -1;
    }

    // Open input file
    FILE *input_file = fopen(argv[3], "r");
    if (input_file == NULL) {
        perror("fopen() error");
        return -1;
    }

    // Allocate stat structure
    struct mm_stats *stats = (struct mm_stats *)malloc(sizeof(struct mm_stats));
    if (!stats) {
        perror("malloc() error");
        return -1;
    }
    memset(stats, 0, sizeof(struct mm_stats));
    stats->log = (struct mm_log *)malloc(sizeof(struct mm_log) * MAX_OPS);
    if (!(stats->log)) {
        perror("malloc() error");
        return -1;
    }
    memset(stats->log, 0, sizeof(struct mm_log) * MAX_OPS);

    // Allocate memory for operation
    struct command *op = (struct command *)malloc(sizeof(struct command));
    if (!op) {
        perror("malloc() error");
        return -1;
    }

    // Get page size
    long PAGE_SIZE = sysconf(_SC_PAGE_SIZE);

    // Options
    int vm_size = 16 * PAGE_SIZE;

    // Allocate aligned memory
    void *vm_ptr;
    int ret = posix_memalign(&vm_ptr, PAGE_SIZE, vm_size);
    if (ret) {
        fprintf(stderr, "posix_memalign failed\n");
        return -1;
    }

    // Init your memory manager
    mm_init(policy, vm_ptr, vm_size, num_frames, PAGE_SIZE, stats);

    // Do Read/Write Operations
    char *vm_ptr_char = (char *)vm_ptr; // Cast void* to char* for pointer arithmetic
    while (read_next_op(input_file, op)) {
        if (strcmp(op->operation, "read") == 0) {
            int read_value = vm_ptr_char[(op->startOffset * 4) + (op->pageNumber * PAGE_SIZE)];
            (void)read_value; // assume we use the read value somewhere
        } else if (strcmp(op->operation, "write") == 0) {
            vm_ptr_char[(op->startOffset * 4) + (op->pageNumber * PAGE_SIZE)] = op->value;
        } else {
            fprintf(stderr, "Incorrect input file content\n");
            return -1;
        }
    }

    mm_finish();

    fclose(input_file);

    // Open output file
    char output_filename[512] = {0};
    mkdir("output", 0755);
    strcat(output_filename, "output/result-");
    strcat(output_filename, argv[1]); // policy
    strcat(output_filename, "-");
    strcat(output_filename, argv[2]); // number of frames
    strcat(output_filename, "-");
    strcat(output_filename, basename(argv[3]));
    FILE *output_file = fopen(output_filename, "w");
    if (output_file == NULL) {
        perror("fopen() error");
        return -1;
    }

    fprintf(output_file, "Page Size: %ld\n", PAGE_SIZE);
    fprintf(output_file, "Num Frames: %d\n", num_frames);
    mm_print_stats(output_file, stats);

    fclose(output_file);
    free(vm_ptr);
    free(op);
    free(stats->log);
    free(stats);

    printf("%s: Output file: %s\n", __func__, output_filename);
    printf("%s: Bye!\n", __func__);
    return 0;
}

bool read_next_op(FILE *fp, struct command *op) {
    char line[MAX_LINE_LEN] = {0};
    if (!fgets(line, MAX_LINE_LEN, fp))
        return false;

    memset(op, 0, sizeof(struct command));

    char *token;
    char delim[2] = " ";
    char *rest = line;

    token = strtok_r(rest, delim, &rest);
    if (token)
        strcpy(op->operation, token);
    else
        return false;

    token = strtok_r(rest, delim, &rest);
    if (token)
        op->pageNumber = atoi(token);
    else
        return false;

    token = strtok_r(rest, delim, &rest);
    if (token)
        op->startOffset = atoi(token);
    else
        return false;

    token = strtok_r(rest, delim, &rest);
    if (token)
        op->value = atoi(token);
    else
        return false;

    if ((strcmp(op->operation, "read") != 0) && (strcmp(op->operation, "write") != 0)) {
        fprintf(stderr, "%s: Invalid operation in input file.\n", __func__);
        exit(EXIT_FAILURE);
    }
    if (op->pageNumber < 0 || op->startOffset < 0) {
        fprintf(stderr, "%s: Invalid number in input file.\n", __func__);
        exit(EXIT_FAILURE);
    }

    return true;
}

void mm_print_stats(FILE *fp, struct mm_stats *stats) {
    fprintf(fp, "type\tvirt-page\tevicted-virt-page\twrite-back\tphy-addr\n");
    for (int i = 0; i < stats->counter; i++) {
        fprintf(fp, "%d\t\t%d\t\t%d\t\t%d\t\t0x%04lx\n",
                stats->log[i].fault_type, stats->log[i].virt_page, stats->log[i].evicted_page,
                stats->log[i].write_back, stats->log[i].phy_addr);
    }
}
