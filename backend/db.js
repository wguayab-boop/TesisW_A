"use strict";

const { Pool } = require("pg");

// En el alojamiento utiliza DATABASE_URL.
// En tu computadora utiliza las variables PG del archivo .env.
const configuracion = process.env.DATABASE_URL
  ? {
      connectionString: process.env.DATABASE_URL
    }
  : {
      user: process.env.PGUSER || "postgres",
      host: process.env.PGHOST || "localhost",
      database: process.env.PGDATABASE || "gestion_comercial",
      password: process.env.PGPASSWORD,
      port: Number(process.env.PGPORT || 5432)
    };

const pool = new Pool({
  ...configuracion,
  connectionTimeoutMillis: 10000
});

pool.on("error", (error) => {
  console.error(
    "Error en una conexión PostgreSQL:",
    error.message
  );
});

module.exports = pool;