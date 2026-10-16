const { Pool } = require("pg");

const pool = new Pool({
  user: "postgres",
  host: "localhost",
  database: "gestion_comercial",
  password: "nellypaulina",
  port: 5432,
  connectionTimeoutMillis: 5000
});

module.exports = pool;