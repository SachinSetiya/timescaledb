/*
 * This file and its contents are licensed under the Timescale License.
 * Please see the included NOTICE for copyright information and
 * LICENSE-TIMESCALE for a copy of the license.
 */
#ifndef TIMESCALEDB_TSL_CHUNK_H
#define TIMESCALEDB_TSL_CHUNK_H

#include <postgres.h>
#include <fmgr.h>
#include <chunk.h>

extern bool chunk_update_foreign_server_if_needed(const Chunk *chunk, Oid data_node_id,
												  bool available);
extern Datum chunk_set_default_data_node(PG_FUNCTION_ARGS);
extern Datum chunk_drop_replica(PG_FUNCTION_ARGS);
extern int chunk_invoke_drop_chunks(Oid relid, Datum older_than, Datum older_than_type);
extern Datum chunk_create_replica_table(PG_FUNCTION_ARGS);

#endif /* TIMESCALEDB_TSL_CHUNK_H */
