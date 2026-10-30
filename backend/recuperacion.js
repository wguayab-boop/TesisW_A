'use strict';

const crypto = require('node:crypto');
const bcrypt = require('bcryptjs');
const nodemailer = require('nodemailer');

module.exports = function instalarRecuperacion(app, pool) {
  const intentos = new Map();

  // Limita los intentos desde una misma dirección.
  function limitarIntentos(req, res, next) {
    const ahora = Date.now();

    for (const [clave, valor] of intentos) {
      if (valor.fin <= ahora) {
        intentos.delete(clave);
      }
    }

    const clave = `${req.ip}:${req.path}`;
    let registro = intentos.get(clave);

    if (!registro || registro.fin <= ahora) {
      registro = {
        cantidad: 0,
        fin: ahora + 15 * 60 * 1000
      };

      intentos.set(clave, registro);
    }

    registro.cantidad += 1;

    if (registro.cantidad > 10) {
      return res.status(429).json({
        mensaje: 'Demasiados intentos. Vuelve a intentarlo más tarde.'
      });
    }

    next();
  }

  // Solicita el enlace de recuperación.
  app.post(
    '/recuperar-password',
    limitarIntentos,
    async (req, res) => {
      const direccionBase = process.env.APP_BASE_URL;
      const correoSistema = process.env.GMAIL_USER;
      const claveAplicacion = process.env.GMAIL_APP_PASSWORD;

      if (!direccionBase || !correoSistema || !claveAplicacion) {
        return res.status(503).json({
          mensaje: 'El envío de correo aún no está configurado.'
        });
      }

      const correo = typeof req.body?.correo === 'string'
        ? req.body.correo.trim().toLowerCase()
        : '';

      if (
        correo.length > 150 ||
        !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(correo)
      ) {
        return res.status(400).json({
          mensaje: 'Escribe un correo válido.'
        });
      }

      try {
        // El usuario recibe el token; la base de datos guarda su hash.
        const token = crypto.randomBytes(32).toString('hex');

        const tokenHash = crypto
          .createHash('sha256')
          .update(token)
          .digest('hex');

        const resultado = await pool.query(
          `UPDATE usuarios
           SET reset_token_hash = $1,
               reset_token_expira = NOW() + INTERVAL '30 minutes'
           WHERE correo = $2 AND activo = TRUE
           RETURNING correo`,
          [tokenHash, correo]
        );

        if (resultado.rowCount) {
          const enlace = new URL('/admin/', direccionBase);
          enlace.searchParams.set('reset', token);

          const transporte = nodemailer.createTransport({
            service: 'gmail',
            auth: {
              user: correoSistema,
              pass: claveAplicacion
            }
          });

          try {
            await transporte.sendMail({
              from: correoSistema,
              to: correo,
              subject:
                'SMARTMARKET: recuperar contraseña / reset password',

              text:
                'Para crear una nueva contraseña, abre este enlace ' +
                'en la computadora donde funciona SMARTMARKET:\n\n' +
                enlace.href +
                '\n\nEl enlace vence en 30 minutos y se puede usar ' +
                'una sola vez.\n\n' +
                'To reset your password, open the link above. ' +
                'It expires in 30 minutes and can be used once.'
            });
          } catch (error) {
            console.error(
              'No se pudo enviar el correo de recuperación:',
              error.message
            );
          }
        }

        // La respuesta es igual exista o no la cuenta.
        return res.json({
          mensaje:
            'Si el correo está registrado, recibirás instrucciones ' +
            'para recuperar tu contraseña.'
        });
      } catch (error) {
        console.error(
          'Error en recuperación de contraseña:',
          error.message
        );

        return res.status(500).json({
          mensaje: 'No se pudo procesar la solicitud.'
        });
      }
    }
  );

  // Comprueba el enlace y cambia la contraseña.
  app.post(
    '/restablecer-password',
    limitarIntentos,
    async (req, res) => {
      const { token, password } = req.body || {};

      if (
        typeof token !== 'string' ||
        !/^[a-f0-9]{64}$/.test(token) ||
        typeof password !== 'string' ||
        password.length < 8 ||
        Buffer.byteLength(password, 'utf8') > 72
      ) {
        return res.status(400).json({
          mensaje: 'Enlace o contraseña inválidos.'
        });
      }

      try {
        const tokenHash = crypto
          .createHash('sha256')
          .update(token)
          .digest('hex');

        const passwordHash = await bcrypt.hash(password, 12);

        // La actualización consume el enlace en la misma operación.
        const resultado = await pool.query(
          `UPDATE usuarios
           SET password_hash = $1,
               reset_token_hash = NULL,
               reset_token_expira = NULL
           WHERE reset_token_hash = $2
             AND reset_token_expira > NOW()
             AND activo = TRUE
           RETURNING id`,
          [passwordHash, tokenHash]
        );

        if (!resultado.rowCount) {
          return res.status(400).json({
            mensaje:
              'El enlace no es válido, ya fue usado o caducó.'
          });
        }

        return res.json({
          mensaje:
            'Contraseña actualizada. Ya puedes iniciar sesión.'
        });
      } catch (error) {
        console.error(
          'Error al restablecer contraseña:',
          error.message
        );

        return res.status(500).json({
          mensaje: 'No se pudo cambiar la contraseña.'
        });
      }
    }
  );
};