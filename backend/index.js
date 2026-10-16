const path = require("node:path");
const { loadEnvFile } = require("node:process");
loadEnvFile(path.join(__dirname, ".env"));
const express = require("express");
const cors = require("cors");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const pool = require("./db");
const JWT_SECRET = process.env.JWT_SECRET;
if (!JWT_SECRET || JWT_SECRET.length < 64) {
  throw new Error("Falta una clave JWT_SECRET válida en .env");
}
const app = express();
const PORT = 3000;
app.use(cors());
app.use(express.json());
app.use("/admin", express.static(path.join(__dirname, "public")));
app.get("/", (req, res) => {
  res.json({
    mensaje: "API de SMARTMARKET-GUAYAQUIL funcionando correctamente"
  });
});
app.get("/test-db", async (req, res) => {
  try {
    const resultado = await pool.query("SELECT NOW() AS fecha");
    res.json({
      mensaje: "Conexión con PostgreSQL exitosa",
      fecha: resultado.rows[0].fecha
    });
  } catch (error) {
    console.error("Error de conexión con PostgreSQL:", error.message);
    res.status(500).json({
      mensaje: "No se pudo conectar con PostgreSQL"
    });
  }
});
app.post("/registro", async (req, res) => {
  const { nombre, correo, password } = req.body || {};
  if (
    typeof nombre !== "string" ||
    typeof correo !== "string" ||
    typeof password !== "string"
  ) {
    return res.status(400).json({
      mensaje: "Debes enviar nombre, correo y contraseña"
    });
  }
  const nombreLimpio = nombre.trim();
  const correoLimpio = correo.trim().toLowerCase();
  if (
    !nombreLimpio ||
    nombreLimpio.length > 100 ||
    correoLimpio.length > 150 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(correoLimpio)
  ) {
    return res.status(400).json({
      mensaje: "Revisa el nombre y el correo"
    });
  }
  if (password.length < 8 || Buffer.byteLength(password, "utf8") > 72) {
    return res.status(400).json({
      mensaje: "La contraseña debe tener al menos 8 caracteres y máximo 72 bytes"
    });
  }
  try {
    const passwordHash = await bcrypt.hash(password, 12);
    const resultado = await pool.query(
      `INSERT INTO usuarios (nombre, correo, password_hash)
       VALUES ($1, $2, $3)
       RETURNING id, nombre, correo, rol`,
      [nombreLimpio, correoLimpio, passwordHash]
    );
    return res.status(201).json({
      mensaje: "Usuario registrado correctamente",
      usuario: resultado.rows[0]
    });
  } catch (error) {
    if (error.code === "23505") {
      return res.status(409).json({
        mensaje: "Ese correo ya está registrado"
      });
    }
    console.error("Error al registrar usuario:", error.message);
    return res.status(500).json({
      mensaje: "No se pudo registrar el usuario"
    });
  }
});
app.post("/login", async (req, res) => {
  const { correo, password } = req.body || {};
  if (
    typeof correo !== "string" ||
    typeof password !== "string" ||
    !correo.trim() ||
    !password ||
    correo.trim().length > 150 ||
    Buffer.byteLength(password, "utf8") > 72
  ) {
    return res.status(400).json({
      mensaje: "Debes enviar un correo y una contraseña válidos"
    });
  }
  try {
    const resultado = await pool.query(
      `SELECT id, nombre, correo, password_hash, rol, activo
       FROM usuarios
       WHERE correo = $1`,
      [correo.trim().toLowerCase()]
    );
    const usuario = resultado.rows[0];
    if (!usuario) {
      return res.status(401).json({
        mensaje: "Correo o contraseña incorrectos"
      });
    }
    const passwordCorrecto = await bcrypt.compare(
      password,
      usuario.password_hash
    );
    if (!passwordCorrecto || !usuario.activo) {
      return res.status(401).json({
        mensaje: "Correo o contraseña incorrectos"
      });
    }
    const token = jwt.sign({}, JWT_SECRET, {
      algorithm: "HS256",
      subject: String(usuario.id),
      expiresIn: "1h"
    });
    return res.json({
      mensaje: "Inicio de sesión exitoso",
      token,
      usuario: {
        id: usuario.id,
        nombre: usuario.nombre,
        correo: usuario.correo,
        rol: usuario.rol
      }
    });
  } catch (error) {
    console.error("Error al verificar credenciales:", error.message);
    return res.status(500).json({
      mensaje: "No se pudo verificar el inicio de sesión"
    });
  }
});
async function verificarToken(req, res, next) {
  const autorizacion = req.get("Authorization") || "";
  const coincidencia = autorizacion.match(/^Bearer\s+(\S+)$/i);
  if (!coincidencia) {
    return res.status(401).json({
      mensaje: "Debes enviar un token de acceso"
    });
  }
  let datos;
  try {
    datos = jwt.verify(coincidencia[1], JWT_SECRET, {
      algorithms: ["HS256"]
    });
    if (
      typeof datos !== "object" ||
      typeof datos.sub !== "string" ||
      !/^[1-9]\d*$/.test(datos.sub) ||
      !Number.isSafeInteger(datos.exp)
    ) {
      throw new Error("Token inválido");
    }
  } catch (error) {
    return res.status(401).json({
      mensaje: "Token inválido o vencido"
    });
  }
  try {
    const resultado = await pool.query(
      `SELECT id, nombre, correo, rol
       FROM usuarios
       WHERE id::text = $1 AND activo = TRUE`,
      [datos.sub]
    );
    if (!resultado.rows[0]) {
      return res.status(401).json({
        mensaje: "Usuario no disponible"
      });
    }
    req.usuario = resultado.rows[0];
    return next();
  } catch (error) {
    console.error("Error al verificar usuario:", error.message);
    return res.status(500).json({
      mensaje: "No se pudo comprobar el acceso"
    });
  }
}
app.get("/perfil", verificarToken, (req, res) => {
  res.json({
    mensaje: "Acceso autorizado",
    usuario: req.usuario
  });
});
app.get("/productos", verificarToken, async (req, res) => {
  try {
    const resultado = await pool.query(
      `SELECT id, nombre, descripcion, precio
       FROM productos
       WHERE activo = TRUE
       ORDER BY nombre, id`
    );
    return res.json({
      productos: resultado.rows
    });
  } catch (error) {
    console.error("Error al consultar productos:", error.message);
    return res.status(500).json({
      mensaje: "No se pudieron consultar los productos"
    });
  }
});
app.post("/productos", verificarToken, async (req, res) => {
  const { nombre, descripcion, precio } = req.body || {};
  if (
    typeof nombre !== "string" ||
    !nombre.trim() ||
    nombre.trim().length > 150
  ) {
    return res.status(400).json({
      mensaje: "El nombre es obligatorio y admite hasta 150 caracteres"
    });
  }
  if (
    descripcion !== undefined &&
    typeof descripcion !== "string"
  ) {
    return res.status(400).json({
      mensaje: "La descripción debe ser un texto"
    });
  }
  // Acepta precios como 1.50 o "1,50".
  if (typeof precio !== "string" && typeof precio !== "number") {
    return res.status(400).json({
      mensaje: "Debes ingresar un precio válido"
    });
  }
  const precioTexto = String(precio).trim().replace(",", ".");
  if (!/^\d{1,10}(\.\d{1,2})?$/.test(precioTexto)) {
    return res.status(400).json({
      mensaje: "El precio debe ser positivo o cero y tener máximo 2 decimales"
    });
  }
  try {
    const resultado = await pool.query(
      `INSERT INTO productos (nombre, descripcion, precio)
       VALUES ($1, $2, $3)
       RETURNING id, nombre, descripcion, precio`,
      [
        nombre.trim(),
        descripcion?.trim() || null,
        precioTexto
      ]
    );
    return res.status(201).json({
      mensaje: "Producto registrado correctamente",
      producto: resultado.rows[0]
    });
  } catch (error) {
    console.error("Error al registrar producto:", error.message);
    return res.status(500).json({
      mensaje: "No se pudo registrar el producto"
    });
  }
});
app.put("/productos/:id", verificarToken, async (req, res) => {
  const { id } = req.params;
  const { nombre, descripcion, precio } = req.body || {};
  if (!/^[1-9]\d*$/.test(id) || Number(id) > 2147483647) {
    return res.status(400).json({
      mensaje: "El identificador del producto no es válido"
    });
  }
  if (
    typeof nombre !== "string" ||
    !nombre.trim() ||
    nombre.trim().length > 150
  ) {
    return res.status(400).json({
      mensaje: "El nombre es obligatorio y admite hasta 150 caracteres"
    });
  }
  if (
    descripcion !== undefined &&
    typeof descripcion !== "string"
  ) {
    return res.status(400).json({
      mensaje: "La descripción debe ser un texto"
    });
  }
  if (typeof precio !== "string" && typeof precio !== "number") {
    return res.status(400).json({
      mensaje: "Debes ingresar un precio válido"
    });
  }
  const precioTexto = String(precio).trim().replace(",", ".");
  if (!/^\d{1,10}(\.\d{1,2})?$/.test(precioTexto)) {
    return res.status(400).json({
      mensaje: "El precio debe ser positivo o cero y tener máximo 2 decimales"
    });
  }
  try {
    const resultado = await pool.query(
      `UPDATE productos
       SET nombre = $1,
           descripcion = $2,
           precio = $3
       WHERE id = $4 AND activo = TRUE
       RETURNING id, nombre, descripcion, precio`,
      [
        nombre.trim(),
        descripcion?.trim() || null,
        precioTexto,
        id
      ]
    );
    if (resultado.rows.length === 0) {
      return res.status(404).json({
        mensaje: "El producto no existe o está inactivo"
      });
    }
    return res.json({
      mensaje: "Producto actualizado correctamente",
      producto: resultado.rows[0]
    });
  } catch (error) {
    console.error("Error al actualizar producto:", error.message);
    return res.status(500).json({
      mensaje: "No se pudo actualizar el producto"
    });
  }
});
app.patch(
  "/productos/:id/desactivar",
  verificarToken,
  async (req, res) => {
    const { id } = req.params;
    if (!/^[1-9]\d*$/.test(id) || Number(id) > 2147483647) {
      return res.status(400).json({
        mensaje: "El identificador del producto no es válido"
      });
    }
    try {
      const resultado = await pool.query(
        `UPDATE productos
         SET activo = FALSE
         WHERE id = $1
         RETURNING id, nombre, activo`,
        [id]
      );
      if (resultado.rows.length === 0) {
        return res.status(404).json({
          mensaje: "El producto no existe"
        });
      }
      return res.json({
        mensaje: "Producto desactivado correctamente",
        producto: resultado.rows[0]
      });
    } catch (error) {
      console.error(
        "Error al desactivar producto:",
        error.message
      );
      return res.status(500).json({
        mensaje: "No se pudo desactivar el producto"
      });
    }
  }
);
// Consultar las existencias de los productos activos.
app.get("/inventario", verificarToken, async (req, res) => {
  try {
    const resultado = await pool.query(
      `SELECT
         p.id AS producto_id,
         p.nombre,
         COALESCE(i.existencia, 0) AS existencia
       FROM productos p
       LEFT JOIN inventario i ON i.producto_id = p.id
       WHERE p.activo = TRUE
       ORDER BY p.nombre, p.id`
    );
    return res.json({
      inventario: resultado.rows
    });
  } catch (error) {
    console.error("Error al consultar inventario:", error.message);
    return res.status(500).json({
      mensaje: "No se pudo consultar el inventario"
    });
  }
});
// Registrar una entrada o salida.
app.post(
  "/inventario/movimientos",
  verificarToken,
  async (req, res) => {
    const { producto_id, tipo, cantidad, motivo } = req.body || {};
    if (
      !Number.isInteger(producto_id) ||
      producto_id < 1 ||
      producto_id > 2147483647
    ) {
      return res.status(400).json({
        mensaje: "Selecciona un producto válido"
      });
    }
    if (tipo !== "entrada" && tipo !== "salida") {
      return res.status(400).json({
        mensaje: "El tipo debe ser entrada o salida"
      });
    }
    if (
      !Number.isInteger(cantidad) ||
      cantidad < 1 ||
      cantidad > 2147483647
    ) {
      return res.status(400).json({
        mensaje: "La cantidad debe ser un número entero mayor que cero"
      });
    }
    if (
      typeof motivo !== "string" ||
      !motivo.trim() ||
      motivo.trim().length > 250
    ) {
      return res.status(400).json({
        mensaje: "El motivo es obligatorio y admite hasta 250 caracteres"
      });
    }
    let cliente;
    try {
      cliente = await pool.connect();
      await cliente.query("BEGIN");
      // Bloqueamos el producto mientras registramos el movimiento.
      const producto = await cliente.query(
        `SELECT id
         FROM productos
         WHERE id = $1 AND activo = TRUE
         FOR UPDATE`,
        [producto_id]
      );
      if (producto.rows.length === 0) {
        await cliente.query("ROLLBACK");
        return res.status(404).json({
          mensaje: "El producto no existe o está inactivo"
        });
      }
      // También prepara productos registrados después de crear las tablas.
      await cliente.query(
        `INSERT INTO inventario (producto_id)
         VALUES ($1)
         ON CONFLICT (producto_id) DO NOTHING`,
        [producto_id]
      );
      const inventario = await cliente.query(
        `SELECT existencia
         FROM inventario
         WHERE producto_id = $1
         FOR UPDATE`,
        [producto_id]
      );
      const anterior = inventario.rows[0].existencia;
      const nueva = tipo === "entrada"
        ? anterior + cantidad
        : anterior - cantidad;
      if (nueva < 0) {
        await cliente.query("ROLLBACK");
        return res.status(409).json({
          mensaje: "No hay existencias suficientes para esa salida",
          existencia: anterior
        });
      }
      if (nueva > 2147483647) {
        await cliente.query("ROLLBACK");
        return res.status(400).json({
          mensaje: "La entrada supera el límite de existencias permitido"
        });
      }
      await cliente.query(
        `UPDATE inventario
         SET existencia = $1,
             fecha_actualizacion = NOW()
         WHERE producto_id = $2`,
        [nueva, producto_id]
      );
      const movimiento = await cliente.query(
        `INSERT INTO movimientos_inventario (
           producto_id,
           usuario_id,
           tipo,
           cantidad,
           motivo,
           existencia_anterior,
           existencia_nueva
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING *`,
        [
          producto_id,
          req.usuario.id,
          tipo,
          cantidad,
          motivo.trim(),
          anterior,
          nueva
        ]
      );
      await cliente.query("COMMIT");
      return res.status(201).json({
        mensaje: "Movimiento registrado correctamente",
        movimiento: movimiento.rows[0]
      });
    } catch (error) {
      if (cliente) {
        try {
          await cliente.query("ROLLBACK");
        } catch (errorRollback) {
          console.error(
            "Error al revertir movimiento:",
            errorRollback.message
          );
        }
      }
      console.error(
        "Error al registrar movimiento:",
        error.message
      );
      return res.status(500).json({
        mensaje: "No se pudo registrar el movimiento"
      });
    } finally {
      if (cliente) {
        cliente.release();
      }
    }
  }
);
function validarCliente(body) {
  const limites = { nombre: 150, identificacion: 20, telefono: 30, correo: 150, direccion: 250 };
  const datos = {};
  for (const [campo, limite] of Object.entries(limites)) {
    const valor = body?.[campo];
    if (valor !== undefined && valor !== null && typeof valor !== 'string') {
      return { error: `El campo ${campo} debe ser un texto` };
    }
    const texto = (valor ?? '').trim();
    if (texto.length > limite) return { error: `${campo}: máximo ${limite} caracteres` };
    datos[campo] = texto || null;
  }
  if (!datos.nombre) return { error: 'El nombre del cliente es obligatorio' };
  if (datos.correo) {
    datos.correo = datos.correo.toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(datos.correo)) return { error: 'El correo no es válido' };
  }
  return { datos };
}
function idClienteValido(id) {
  return /^[1-9]\d*$/.test(id) && Number(id) <= 2147483647;
}
app.get('/clientes', verificarToken, async (req, res) => {
  try {
    const resultado = await pool.query(`SELECT id, nombre, identificacion, telefono, correo, direccion
      FROM clientes WHERE activo = TRUE ORDER BY nombre, id`);
    return res.json({ clientes: resultado.rows });
  } catch (error) {
    console.error('Error al consultar clientes:', error.message);
    return res.status(500).json({ mensaje: 'No se pudieron consultar los clientes' });
  }
});
app.post('/clientes', verificarToken, async (req, res) => {
  const validacion = validarCliente(req.body);
  if (validacion.error) return res.status(400).json({ mensaje: validacion.error });
  const d = validacion.datos;
  try {
    const resultado = await pool.query(`INSERT INTO clientes (nombre, identificacion, telefono, correo, direccion)
      VALUES ($1,$2,$3,$4,$5) RETURNING id, nombre, identificacion, telefono, correo, direccion`,
      [d.nombre, d.identificacion, d.telefono, d.correo, d.direccion]);
    return res.status(201).json({ mensaje: 'Cliente registrado correctamente', cliente: resultado.rows[0] });
  } catch (error) {
    console.error('Error al registrar cliente:', error.message);
    return res.status(500).json({ mensaje: 'No se pudo registrar el cliente' });
  }
});
app.put('/clientes/:id', verificarToken, async (req, res) => {
  if (!idClienteValido(req.params.id)) return res.status(400).json({ mensaje: 'Identificador de cliente inválido' });
  const validacion = validarCliente(req.body);
  if (validacion.error) return res.status(400).json({ mensaje: validacion.error });
  const d = validacion.datos;
  try {
    const resultado = await pool.query(`UPDATE clientes SET nombre=$1, identificacion=$2, telefono=$3, correo=$4, direccion=$5
      WHERE id=$6 AND activo=TRUE RETURNING id, nombre, identificacion, telefono, correo, direccion`,
      [d.nombre, d.identificacion, d.telefono, d.correo, d.direccion, req.params.id]);
    if (!resultado.rows[0]) return res.status(404).json({ mensaje: 'El cliente no existe o está inactivo' });
    return res.json({ mensaje: 'Cliente actualizado correctamente', cliente: resultado.rows[0] });
  } catch (error) {
    console.error('Error al actualizar cliente:', error.message);
    return res.status(500).json({ mensaje: 'No se pudo actualizar el cliente' });
  }
});
app.patch('/clientes/:id/desactivar', verificarToken, async (req, res) => {
  if (!idClienteValido(req.params.id)) return res.status(400).json({ mensaje: 'Identificador de cliente inválido' });
  try {
    const resultado = await pool.query('UPDATE clientes SET activo=FALSE WHERE id=$1 RETURNING id, nombre, activo', [req.params.id]);
    if (!resultado.rows[0]) return res.status(404).json({ mensaje: 'El cliente no existe' });
    return res.json({ mensaje: 'Cliente desactivado correctamente', cliente: resultado.rows[0] });
  } catch (error) {
    console.error('Error al desactivar cliente:', error.message);
    return res.status(500).json({ mensaje: 'No se pudo desactivar el cliente' });
  }
});
// VENTAS: pegar antes de app.listen.
function enteroVenta(valor) {
  return Number.isInteger(valor) && valor > 0 && valor <= 2147483647;
}
app.get('/ventas', verificarToken, async (req, res) => {
  let f;
  try { f = filtrosConsulta(req.query); }
  catch (e) { return res.status(400).json({mensaje:e.message}); }
  try {
    const r=await pool.query(`SELECT v.id,v.cliente_id,c.nombre AS cliente_nombre,
      v.total,v.estado,v.observacion,v.fecha_creacion FROM ventas v JOIN clientes c ON c.id=v.cliente_id
      WHERE ($1::date IS NULL OR (v.fecha_creacion AT TIME ZONE 'America/Guayaquil')::date >= $1::date)
        AND ($2::date IS NULL OR (v.fecha_creacion AT TIME ZONE 'America/Guayaquil')::date <= $2::date)
        AND ($3='' OR POSITION(LOWER($3) IN LOWER(c.nombre))>0 OR v.id::text=$3)
      ORDER BY v.fecha_creacion DESC,v.id DESC LIMIT 200`,[f.desde,f.hasta,f.busqueda]);
    res.json({ventas:r.rows});
  } catch(e) { console.error('Error al consultar ventas:',e.message);res.status(500).json({mensaje:'No se pudieron consultar las ventas'}); }
});
app.get('/ventas/:id', verificarToken, async (req, res) => {
  if (!/^[1-9]\d*$/.test(req.params.id) || Number(req.params.id)>2147483647) {
    return res.status(400).json({mensaje:'Identificador de venta inválido'});
  }
  try {
    const r = await pool.query(`SELECT v.*, c.nombre AS cliente_nombre
      FROM ventas v JOIN clientes c ON c.id=v.cliente_id WHERE v.id=$1`, [req.params.id]);
    if (!r.rows[0]) return res.status(404).json({mensaje:'La venta no existe'});
    const d = await pool.query(`SELECT producto_id, nombre_producto, cantidad, precio_unitario, subtotal
      FROM detalle_ventas WHERE venta_id=$1 ORDER BY id`, [req.params.id]);
    res.json({venta:r.rows[0], detalle:d.rows});
  } catch (e) {
    console.error('Error al consultar venta:', e.message);
    res.status(500).json({mensaje:'No se pudo consultar la venta'});
  }
});
app.post('/ventas', verificarToken, async (req,res) => {
  const {cliente_id, productos, observacion} = req.body || {};
  if (!enteroVenta(cliente_id)) return res.status(400).json({mensaje:'Selecciona un cliente válido'});
  if (!Array.isArray(productos) || productos.length<1 || productos.length>100) {
    return res.status(400).json({mensaje:'Agrega entre 1 y 100 productos'});
  }
  if (observacion != null && (typeof observacion !== 'string' || observacion.trim().length>250)) {
    return res.status(400).json({mensaje:'La observación admite hasta 250 caracteres'});
  }
  const ids = new Set();
  for (const p of productos) {
    if (!p || !enteroVenta(p.producto_id) || !enteroVenta(p.cantidad) || ids.has(p.producto_id)) {
      return res.status(400).json({mensaje:'Revisa los productos y sus cantidades; no repitas productos'});
    }
    ids.add(p.producto_id);
  }
  const orden = [...productos].sort((a,b)=>a.producto_id-b.producto_id);
  let db;
  try {
    db = await pool.connect();
    await db.query('BEGIN');
    const c = await db.query('SELECT id FROM clientes WHERE id=$1 AND activo=TRUE FOR SHARE',[cliente_id]);
    if (!c.rows[0]) {
      await db.query('ROLLBACK');
      return res.status(409).json({mensaje:'El cliente ya no está disponible'});
    }
    const lineas = [];
    let total = 0n;
    for (const item of orden) {
      const p = await db.query('SELECT id, nombre, precio FROM productos WHERE id=$1 AND activo=TRUE FOR UPDATE',[item.producto_id]);
      if (!p.rows[0]) {
        await db.query('ROLLBACK');
        return res.status(409).json({mensaje:'Uno de los productos ya no está disponible'});
      }
      await db.query('INSERT INTO inventario (producto_id) VALUES ($1) ON CONFLICT (producto_id) DO NOTHING',[item.producto_id]);
      const i = await db.query('SELECT existencia FROM inventario WHERE producto_id=$1 FOR UPDATE',[item.producto_id]);
      const anterior = i.rows[0].existencia;
      if (anterior < item.cantidad) {
        await db.query('ROLLBACK');
        return res.status(409).json({mensaje:`Stock insuficiente para ${p.rows[0].nombre}. Disponible: ${anterior}`});
      }
      // Centavos enteros: no calculamos dinero con decimales binarios.
      const precio = String(p.rows[0].precio);
      if (!/^\d{1,10}\.\d{2}$/.test(precio)) throw new Error('Precio fuera del rango permitido');
      const centavos = BigInt(precio.replace('.',''));
      const subtotal = centavos * BigInt(item.cantidad);
      total += subtotal;
      if (total > 99999999999999n) {
        await db.query('ROLLBACK');
        return res.status(400).json({mensaje:'El total supera el límite permitido'});
      }
      lineas.push({...item, nombre:p.rows[0].nombre, precio, subtotal, anterior});
    }
    const dinero = n => `${n / 100n}.${String(n % 100n).padStart(2,'0')}`;
    const v = await db.query(`INSERT INTO ventas (cliente_id,usuario_id,total,observacion)
      VALUES ($1,$2,$3,$4) RETURNING *`,[cliente_id,req.usuario.id,dinero(total),observacion?.trim() || null]);
    const venta = v.rows[0];
    for (const l of lineas) {
      await db.query(`INSERT INTO detalle_ventas (venta_id,producto_id,nombre_producto,cantidad,precio_unitario,subtotal)
        VALUES ($1,$2,$3,$4,$5,$6)`,[venta.id,l.producto_id,l.nombre,l.cantidad,l.precio,dinero(l.subtotal)]);
      await db.query('UPDATE inventario SET existencia=$1, fecha_actualizacion=NOW() WHERE producto_id=$2',[l.anterior-l.cantidad,l.producto_id]);
      await db.query(`INSERT INTO movimientos_inventario
        (producto_id,usuario_id,tipo,cantidad,motivo,existencia_anterior,existencia_nueva)
        VALUES ($1,$2,'salida',$3,$4,$5,$6)`,
        [l.producto_id,req.usuario.id,l.cantidad,`Venta #${venta.id}`,l.anterior,l.anterior-l.cantidad]);
    }
    await db.query('COMMIT');
    res.status(201).json({mensaje:'Venta registrada correctamente',venta});
  } catch (e) {
    if (db) { try { await db.query('ROLLBACK'); } catch (_) {} }
    console.error('Error al registrar venta:', e.message);
    res.status(500).json({mensaje:'No se pudo confirmar la venta. Consulta la lista antes de repetirla.'});
  } finally { if (db) db.release(); }
});
function filtrosConsulta(query) {
  const desde = query.desde || '';
  const hasta = query.hasta || '';
  const busqueda = query.busqueda || '';
  if ([desde,hasta,busqueda].some(v=>typeof v!=='string') || busqueda.length>150) {
    throw new Error('Revisa los filtros');
  }
  for (const f of [desde,hasta]) {
    if (f && (!/^\d{4}-\d{2}-\d{2}$/.test(f) || !Number.isFinite(Date.parse(f+'T00:00:00Z')) || new Date(f+'T00:00:00Z').toISOString().slice(0,10)!==f)) {
      throw new Error('Usa fechas válidas con formato AAAA-MM-DD');
    }
  }
  if(desde && hasta && desde>hasta) throw new Error('La fecha inicial debe ser anterior a la final');
  return {desde:desde||null,hasta:hasta||null,busqueda:busqueda.trim()};
}
app.get('/resumen', verificarToken, async(req,res)=>{
  try{
    const r=await pool.query(`SELECT
      (SELECT COUNT(*)::int FROM ventas WHERE estado='registrada'
        AND (fecha_creacion AT TIME ZONE 'America/Guayaquil')::date=(NOW() AT TIME ZONE 'America/Guayaquil')::date) AS ventas_hoy,
      (SELECT COALESCE(SUM(total),0)::numeric(16,2) FROM ventas WHERE estado='registrada'
        AND (fecha_creacion AT TIME ZONE 'America/Guayaquil')::date=(NOW() AT TIME ZONE 'America/Guayaquil')::date) AS total_hoy,
      (SELECT COUNT(*)::int FROM clientes WHERE activo=TRUE) AS clientes,
      (SELECT COUNT(*)::int FROM productos WHERE activo=TRUE) AS productos,
      (SELECT COUNT(*)::int FROM productos p LEFT JOIN inventario i ON i.producto_id=p.id
        WHERE p.activo=TRUE AND COALESCE(i.existencia,0)=0) AS sin_stock,
      (SELECT COUNT(*)::int FROM productos p LEFT JOIN inventario i ON i.producto_id=p.id
        WHERE p.activo=TRUE AND COALESCE(i.existencia,0) BETWEEN 1 AND 5) AS stock_bajo`);
    res.json({resumen:r.rows[0]});
  }catch(e){console.error('Error en resumen:',e.message);res.status(500).json({mensaje:'No se pudo consultar el resumen'});}
});
app.get('/inventario/historial',verificarToken,async(req,res)=>{
  let f;
  try{f=filtrosConsulta(req.query);}catch(e){return res.status(400).json({mensaje:e.message});}
  const producto=req.query.producto_id||null;
  if(producto && (typeof producto!=='string'|| !/^[1-9]\d*$/.test(producto)||Number(producto)>2147483647)){
    return res.status(400).json({mensaje:'Producto inválido'});
  }
  try{
    const r=await pool.query(`SELECT m.id,m.producto_id,p.nombre,m.tipo,m.cantidad,m.motivo,
      m.existencia_anterior,m.existencia_nueva,m.fecha,u.nombre AS usuario_nombre
      FROM movimientos_inventario m JOIN productos p ON p.id=m.producto_id JOIN usuarios u ON u.id=m.usuario_id
      WHERE ($1::integer IS NULL OR m.producto_id=$1)
        AND ($2::date IS NULL OR (m.fecha AT TIME ZONE 'America/Guayaquil')::date >= $2::date)
        AND ($3::date IS NULL OR (m.fecha AT TIME ZONE 'America/Guayaquil')::date <= $3::date)
        AND ($4='' OR POSITION(LOWER($4) IN LOWER(p.nombre))>0)
      ORDER BY m.fecha DESC,m.id DESC LIMIT 200`,[producto,f.desde,f.hasta,f.busqueda]);
    res.json({movimientos:r.rows});
  }catch(e){console.error('Error en historial:',e.message);res.status(500).json({mensaje:'No se pudo consultar el historial'});}
});
app.patch('/ventas/:id/anular',verificarToken,async(req,res)=>{
  const id=req.params.id;
  if(!/^[1-9]\d*$/.test(id)||Number(id)>2147483647) return res.status(400).json({mensaje:'Venta inválida'});
  let db;
  try{
    db=await pool.connect();await db.query('BEGIN');
    const r=await db.query('SELECT id,estado FROM ventas WHERE id=$1 FOR UPDATE',[id]);
    if(!r.rows[0]){await db.query('ROLLBACK');return res.status(404).json({mensaje:'La venta no existe'});}
    if(r.rows[0].estado==='anulada'){
      await db.query('ROLLBACK');return res.json({mensaje:'La venta ya estaba anulada; no se duplicó la devolución',venta:r.rows[0]});
    }
    const lineas=await db.query('SELECT producto_id,cantidad FROM detalle_ventas WHERE venta_id=$1 ORDER BY producto_id',[id]);
    if(!lineas.rows.length)throw new Error('Venta sin detalle');
    for(const l of lineas.rows){
      await db.query('SELECT id FROM productos WHERE id=$1 FOR UPDATE',[l.producto_id]);
      const i=await db.query('SELECT existencia FROM inventario WHERE producto_id=$1 FOR UPDATE',[l.producto_id]);
      if(!i.rows[0])throw new Error('No existe inventario para el producto');
      const anterior=i.rows[0].existencia,nueva=anterior+l.cantidad;
      if(nueva>2147483647){await db.query('ROLLBACK');return res.status(409).json({mensaje:'La devolución supera el límite de inventario'});}
      await db.query('UPDATE inventario SET existencia=$1,fecha_actualizacion=NOW() WHERE producto_id=$2',[nueva,l.producto_id]);
      await db.query(`INSERT INTO movimientos_inventario
        (producto_id,usuario_id,tipo,cantidad,motivo,existencia_anterior,existencia_nueva)
        VALUES ($1,$2,'entrada',$3,$4,$5,$6)`,[l.producto_id,req.usuario.id,l.cantidad,`Anulación de venta #${id}`,anterior,nueva]);
    }
    const v=await db.query("UPDATE ventas SET estado='anulada' WHERE id=$1 RETURNING id,estado",[id]);
    await db.query('COMMIT');res.json({mensaje:'Venta anulada. Existencias devueltas al inventario.',venta:v.rows[0]});
  }catch(e){
    if(db){try{await db.query('ROLLBACK');}catch(_){}}
    console.error('Error al anular venta:',e.message);res.status(500).json({mensaje:'No se pudo confirmar la anulación. Comprueba el estado de la venta.'});
  }finally{if(db)db.release();}
});
app.listen(PORT, () => {
  console.log(`Servidor funcionando en http://localhost:${PORT}`);
});
