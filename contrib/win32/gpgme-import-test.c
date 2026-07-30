/*
 * Minimal reproducer for gpgme_op_import() returning success with zero keys
 * considered. No libjcat involved.
 *
 * Build (MSYS2 UCRT64):
 *   gcc -o gpgme-import-test gpgme-import-test.c $(pkg-config --cflags --libs gpgme) \
 *     || gcc -o gpgme-import-test gpgme-import-test.c -lgpgme
 *
 * Run:
 *   ./gpgme-import-test GPG-KEY-Linux-Vendor-Firmware-Service /d/JCAT/repro-home
 *
 * Expected: "considered=1 imported=1" (or unchanged=1 on a second run).
 * Bug:      "considered=0 imported=0 unchanged=0" with no error.
 *
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

#include <gpgme.h>
#include <locale.h>
#include <stdio.h>
#include <stdlib.h>

static int
die(const char *what, gpgme_error_t rc)
{
	fprintf(stderr, "%s: %s (%s)\n", what, gpgme_strerror(rc), gpgme_strsource(rc));
	return 1;
}

int
main(int argc, char *argv[])
{
	gpgme_ctx_t ctx = NULL;
	gpgme_data_t data = NULL;
	gpgme_error_t rc;
	gpgme_import_result_t result;
	gpgme_engine_info_t info;
	const char *keyfile;
	const char *homedir;

	if (argc < 3) {
		fprintf(stderr, "usage: %s KEYFILE HOMEDIR\n", argv[0]);
		return 2;
	}
	keyfile = argv[1];
	homedir = argv[2];

	setlocale(LC_ALL, "");
	printf("gpgme %s\n", gpgme_check_version(NULL));
	gpgme_set_locale(NULL, LC_CTYPE, setlocale(LC_CTYPE, NULL));

	rc = gpgme_new(&ctx);
	if (rc != GPG_ERR_NO_ERROR)
		return die("gpgme_new", rc);
	rc = gpgme_set_protocol(ctx, GPGME_PROTOCOL_OpenPGP);
	if (rc != GPG_ERR_NO_ERROR)
		return die("gpgme_set_protocol", rc);
	rc = gpgme_ctx_set_engine_info(ctx, GPGME_PROTOCOL_OpenPGP, NULL, homedir);
	if (rc != GPG_ERR_NO_ERROR)
		return die("gpgme_ctx_set_engine_info", rc);

	for (info = gpgme_ctx_get_engine_info(ctx); info != NULL; info = info->next) {
		if (info->protocol != GPGME_PROTOCOL_OpenPGP)
			continue;
		printf("engine: %s (v%s)\nhomedir: %s\n",
		       info->file_name ? info->file_name : "(none)",
		       info->version ? info->version : "(unknown)",
		       info->home_dir ? info->home_dir : "(default)");
	}

	/* copy=1: read the file into memory, so gpgme must push the bytes to gpg
	 * over a pipe. This is the code path that fails. */
	rc = gpgme_data_new_from_file(&data, keyfile, 1);
	if (rc != GPG_ERR_NO_ERROR)
		return die("gpgme_data_new_from_file", rc);

	rc = gpgme_op_import(ctx, data);
	if (rc != GPG_ERR_NO_ERROR)
		return die("gpgme_op_import", rc);

	result = gpgme_op_import_result(ctx);
	printf("considered=%d imported=%d unchanged=%d not_imported=%d\n",
	       result->considered,
	       result->imported,
	       result->unchanged,
	       result->not_imported);
	for (gpgme_import_status_t s = result->imports; s != NULL; s = s->next)
		printf("  key %s status=%u %s\n", s->fpr, s->status, gpgme_strerror(s->result));

	gpgme_data_release(data);
	gpgme_release(ctx);

	if (result->considered == 0) {
		printf("\nFAILED: gpg reported success but considered no keys\n");
		return 1;
	}
	printf("\nOK\n");
	return 0;
}
