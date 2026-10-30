// ARCHIVO COMPLETO: app_movil/lib/main.dart
// Reemplaza todo el contenido de main.dart con este código.
//
// Recuperación conectada a las rutas de recuperacion.js:
// POST /recuperar-password      {correo}
// POST /restablecer-password    {token, password}
//
// El envío de correo requiere la configuración existente del backend.
// El enlace del correo abre la web. En la app puedes pegar el enlace
// completo o únicamente el token para cambiar la contraseña.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const apiUrl = 'http://10.0.2.2:3000';
const rutaSolicitarRecuperacion = '/recuperar-password';
const rutaCambiarPassword = '/restablecer-password';

const azul = Color(0xFF143653);
const verde = Color(0xFF087F73);
const fondo = Color(0xFFF3F6FA);
const gris = Color(0xFF647589);
const borde = Color(0xFFE0E7EF);

void main() => runApp(const GestionComercialApp());

// ==================== API ====================

class ErrorApi implements Exception {
  final String mensaje;
  final bool incierto;

  const ErrorApi(this.mensaje, {this.incierto = false});

  @override
  String toString() => mensaje;
}

Future<Map<String, dynamic>> api(
  String ruta, {
  String? token,
  String metodo = 'GET',
  Map<String, dynamic>? datos,
}) async {
  final mutacion = metodo != 'GET';

  try {
    final uri = Uri.parse('$apiUrl$ruta');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final body = jsonEncode(datos ?? {});
    final Future<http.Response> peticion;

    switch (metodo) {
      case 'POST':
        peticion = http.post(uri, headers: headers, body: body);
        break;
      case 'PUT':
        peticion = http.put(uri, headers: headers, body: body);
        break;
      case 'PATCH':
        peticion = http.patch(uri, headers: headers, body: body);
        break;
      default:
        peticion = http.get(uri, headers: headers);
    }

    final respuesta =
        await peticion.timeout(const Duration(seconds: 30));

    Map<String, dynamic>? contenido;

    try {
      final valor = jsonDecode(utf8.decode(respuesta.bodyBytes));
      if (valor is Map) {
        contenido = Map<String, dynamic>.from(valor);
      }
    } catch (_) {}

    if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
      throw ErrorApi(
        contenido?['mensaje']?.toString() ??
            contenido?['message']?.toString() ??
            (respuesta.statusCode == 401
                ? 'Sesión vencida o credenciales incorrectas.'
                : 'No se pudo completar la operación '
                    '(${respuesta.statusCode}).'),
        incierto: mutacion && respuesta.statusCode >= 500,
      );
    }

    if (contenido == null) {
      throw ErrorApi(
        'El servidor devolvió una respuesta inesperada.',
        incierto: mutacion,
      );
    }

    return contenido;
  } on ErrorApi {
    rethrow;
  } on TimeoutException {
    throw ErrorApi(
      'El servidor tardó demasiado en responder.',
      incierto: mutacion,
    );
  } catch (_) {
    throw ErrorApi(
      'No se pudo conectar. Comprueba que el backend esté encendido.',
      incierto: mutacion,
    );
  }
}

List<Map<String, dynamic>> lista(dynamic valor) {
  if (valor is! List) {
    throw const ErrorApi('El servidor no devolvió una lista válida.');
  }
  return valor
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}

int numero(dynamic valor) =>
    valor is num ? valor.toInt() : int.tryParse('$valor') ?? 0;

bool correoValido(String valor) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(valor.trim());

String? validarCorreo(String? valor) =>
    correoValido(valor ?? '') ? null : 'Escribe un correo válido';

String? validarPassword(String? valor) {
  final texto = valor ?? '';
  if (texto.length < 8) return 'Utiliza al menos 8 caracteres';
  if (utf8.encode(texto).length > 72) {
    return 'La contraseña supera el máximo de 72 bytes';
  }
  return null;
}

String extraerToken(String texto) {
  final limpio = texto.trim();
  if (RegExp(r'^[a-f0-9]{64}$').hasMatch(limpio)) return limpio;

  final uri = Uri.tryParse(limpio);
  return uri?.queryParameters['reset'] ?? '';
}

int centavos(dynamic valor) {
  final texto = '$valor'.replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(texto)) {
    throw const ErrorApi('Se recibió un precio inválido.');
  }
  final partes = texto.split('.');
  final decimal =
      (partes.length > 1 ? partes[1] : '').padRight(2, '0');
  return int.parse(partes[0]) * 100 + int.parse(decimal);
}

String dinero(int valor) =>
    '${valor ~/ 100}.${(valor % 100).toString().padLeft(2, '0')}';

String fechaLocal(dynamic valor) {
  final fecha = DateTime.tryParse('$valor');
  if (fecha == null) return '$valor';

  final e = fecha.toUtc().subtract(const Duration(hours: 5));
  String dos(int n) => '$n'.padLeft(2, '0');

  return '${dos(e.day)}/${dos(e.month)}/${e.year} '
      '${dos(e.hour)}:${dos(e.minute)}';
}

String consultaFiltros(
  String ruta,
  String busqueda,
  DateTime? desde,
  DateTime? hasta,
) {
  String fecha(DateTime d) =>
      '${d.year}-${'${d.month}'.padLeft(2, '0')}-'
      '${'${d.day}'.padLeft(2, '0')}';

  return Uri(
    path: ruta,
    queryParameters: {
      'busqueda': busqueda.trim(),
      if (desde != null) 'desde': fecha(desde),
      if (hasta != null) 'hasta': fecha(hasta),
    },
  ).toString();
}

void aviso(BuildContext context, String mensaje) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(mensaje)));
}

Future<bool> confirmar(
  BuildContext context,
  String titulo,
  String mensaje,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    ) ??
    false;

// ==================== DISEÑO ====================

class GestionComercialApp extends StatelessWidget {
  const GestionComercialApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Smart Market Guayaquil',
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: fondo,
          colorScheme: ColorScheme.fromSeed(
            seedColor: verde,
            primary: verde,
            secondary: azul,
            surface: Colors.white,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: fondo,
            foregroundColor: azul,
            elevation: 0,
            titleTextStyle: TextStyle(
              color: azul,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 19,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: borde),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: borde),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: verde, width: 2),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 54),
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          floatingActionButtonTheme:
              const FloatingActionButtonThemeData(
            backgroundColor: verde,
            foregroundColor: Colors.white,
          ),
          snackBarTheme: const SnackBarThemeData(
            backgroundColor: azul,
            behavior: SnackBarBehavior.floating,
          ),
        ),
        home: const InicioPage(),
      );
}

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borde),
        ),
        child: child,
      );
}

class Marca extends StatelessWidget {
  final bool clara;
  const Marca({super.key, this.clara = false});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: clara ? Colors.white.withAlpha(22) : verde,
              borderRadius: BorderRadius.circular(27),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              size: 56,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'SMART MARKET',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: clara ? Colors.white : azul,
              fontSize: 33,
              fontWeight: FontWeight.w900,
              height: 1.1,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            'GUAYAQUIL',
            style: TextStyle(
              color: clara ? const Color(0xFFA9E5D8) : verde,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
            ),
          ),
        ],
      );
}

class BannerInfo extends StatelessWidget {
  final String titulo;
  final String texto;
  final IconData icono;

  const BannerInfo({
    super.key,
    required this.titulo,
    required this.texto,
    this.icono = Icons.tips_and_updates_outlined,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFE6F4EF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFCEE8DF)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, color: verde, size: 28),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      color: azul,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    texto,
                    style: const TextStyle(color: gris, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

Widget boton(
  String texto,
  VoidCallback? accion, {
  bool ocupado = false,
  IconData icono = Icons.arrow_forward_rounded,
}) =>
    FilledButton.icon(
      onPressed: ocupado ? null : accion,
      icon: ocupado
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icono),
      label: Text(texto),
    );

Widget fallo(String texto, VoidCallback reintentar) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 50, color: gris),
            const SizedBox(height: 16),
            Text(texto, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: reintentar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );

Widget vacio(String texto) => Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 54, color: gris),
            const SizedBox(height: 16),
            Text(
              texto,
              textAlign: TextAlign.center,
              style: const TextStyle(color: gris, height: 1.5),
            ),
          ],
        ),
      ),
    );

class PaginaAcceso extends StatelessWidget {
  final String titulo;
  final String descripcion;
  final Widget child;

  const PaginaAcceso({
    super.key,
    required this.titulo,
    required this.descripcion,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          top: false,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Marca(),
                    const SizedBox(height: 28),
                    Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            titulo,
                            style: const TextStyle(
                              color: azul,
                              fontSize: 27,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            descripcion,
                            style: const TextStyle(
                              color: gris,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 26),
                          child,
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const BannerInfo(
                      titulo: 'Tu negocio, mejor organizado',
                      texto:
                          'Consulta productos, controla existencias '
                          'y registra tus ventas desde el móvil.',
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'SMART MARKET GUAYAQUIL',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: gris,
                        fontSize: 11,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class CampoPassword extends StatefulWidget {
  final TextEditingController controller;
  final String etiqueta;
  final bool enabled;
  final bool nueva;
  final String? Function(String?)? validator;
  final VoidCallback? enviar;

  const CampoPassword({
    super.key,
    required this.controller,
    this.etiqueta = 'Contraseña',
    this.enabled = true,
    this.nueva = false,
    this.validator,
    this.enviar,
  });

  @override
  State<CampoPassword> createState() => _CampoPasswordState();
}

class _CampoPasswordState extends State<CampoPassword> {
  bool ocultar = true;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controller,
        enabled: widget.enabled,
        obscureText: ocultar,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: [
          widget.nueva
              ? AutofillHints.newPassword
              : AutofillHints.password,
        ],
        textInputAction: widget.enviar == null
            ? TextInputAction.next
            : TextInputAction.done,
        onFieldSubmitted: (_) => widget.enviar?.call(),
        validator: widget.validator,
        decoration: InputDecoration(
          labelText: widget.etiqueta,
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          suffixIcon: IconButton(
            tooltip:
                ocultar ? 'Mostrar contraseña' : 'Ocultar contraseña',
            onPressed: widget.enabled
                ? () => setState(() => ocultar = !ocultar)
                : null,
            icon: Icon(
              ocultar
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
          ),
        ),
      );
}

// ==================== PORTADA ====================

class InicioPage extends StatelessWidget {
  const InicioPage({super.key});

  Widget beneficio(IconData icono, String texto) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: const Color(0xFFA9E5D8), size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF102C49), Color(0xFF155069), verde],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Marca(clara: true),
                      const SizedBox(height: 34),
                      const Text(
                        'Tu negocio.\nSiempre a la mano.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Organiza la gestión de tu emprendimiento '
                        'desde un solo lugar.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFD4E8EB),
                          fontSize: 17,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(18),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withAlpha(30),
                          ),
                        ),
                        child: Column(
                          children: [
                            beneficio(
                              Icons.inventory_2_outlined,
                              'Productos e inventario organizados',
                            ),
                            const SizedBox(height: 18),
                            beneficio(
                              Icons.point_of_sale_rounded,
                              'Registro y consulta de ventas',
                            ),
                            const SizedBox(height: 18),
                            beneficio(
                              Icons.people_alt_outlined,
                              'Información de tus clientes',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: azul,
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LoginPage(),
                          ),
                        ),
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('Iniciar sesión'),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70),
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RegistroPage(),
                          ),
                        ),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('Crear cuenta'),
                      ),
                      const SizedBox(height: 26),
                      const Text(
                        'Gestión comercial para pequeños emprendimientos',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

// ==================== INICIAR SESIÓN ====================

class LoginPage extends StatefulWidget {
  final String correoInicial;
  const LoginPage({super.key, this.correoInicial = ''});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final form = GlobalKey<FormState>();
  final correo = TextEditingController();
  final clave = TextEditingController();
  bool ocupado = false;

  @override
  void initState() {
    super.initState();
    correo.text = widget.correoInicial;
  }

  @override
  void dispose() {
    correo.dispose();
    clave.dispose();
    super.dispose();
  }

  Future<void> ingresar() async {
    if (ocupado || !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => ocupado = true);

    try {
      final d = await api(
        '/login',
        metodo: 'POST',
        datos: {
          'correo': correo.text.trim().toLowerCase(),
          'password': clave.text,
        },
      );

      final token = d['token'];
      if (token is! String || token.isEmpty) {
        throw const ErrorApi('El servidor no devolvió un token válido.');
      }

      final perfil = await api('/perfil', token: token);
      if (perfil['usuario'] is! Map) {
        throw const ErrorApi('No se pudo obtener el perfil.');
      }

      final usuario =
          Map<String, dynamic>.from(perfil['usuario'] as Map);
      if (!mounted) return;

      clave.clear();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => MenuPage(token: token, usuario: usuario),
        ),
        (_) => false,
      );
    } catch (e) {
      if (mounted) aviso(context, '$e');
    } finally {
      if (mounted) setState(() => ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !ocupado,
        child: PaginaAcceso(
          titulo: '¡Bienvenido de nuevo!',
          descripcion:
              'Ingresa con tu cuenta para continuar con tu negocio.',
          child: Form(
            key: form,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: correo,
                    enabled: !ocupado,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                    autocorrect: false,
                    validator: validarCorreo,
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico',
                      hintText: 'nombre@correo.com',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 18),
                  CampoPassword(
                    controller: clave,
                    enabled: !ocupado,
                    enviar: ingresar,
                    validator: (v) => (v ?? '').isEmpty
                        ? 'Escribe tu contraseña'
                        : null,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: ocupado
                          ? null
                          : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => RecuperarPage(
                                    correoInicial: correo.text.trim(),
                                  ),
                                ),
                              ),
                      child: const Text('¿Olvidaste tu contraseña?'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  boton(
                    ocupado ? 'Ingresando...' : 'Iniciar sesión',
                    ingresar,
                    ocupado: ocupado,
                    icono: Icons.login_rounded,
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    '¿Todavía no tienes una cuenta?',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: gris),
                  ),
                  TextButton(
                    onPressed: ocupado
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const RegistroPage(),
                              ),
                            ),
                    child: const Text('Crear mi cuenta'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

// ==================== REGISTRO ====================

class RegistroPage extends StatefulWidget {
  const RegistroPage({super.key});

  @override
  State<RegistroPage> createState() => _RegistroPageState();
}

class _RegistroPageState extends State<RegistroPage> {
  final form = GlobalKey<FormState>();
  final nombre = TextEditingController();
  final correo = TextEditingController();
  final clave = TextEditingController();
  final repetir = TextEditingController();

  bool ocupado = false;
  bool incierto = false;

  @override
  void dispose() {
    nombre.dispose();
    correo.dispose();
    clave.dispose();
    repetir.dispose();
    super.dispose();
  }

  void irLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LoginPage(correoInicial: correo.text.trim()),
      ),
    );
  }

  Future<void> registrar() async {
    if (ocupado || incierto || !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => ocupado = true);

    try {
      await api(
        '/registro',
        metodo: 'POST',
        datos: {
          'nombre': nombre.text.trim(),
          'correo': correo.text.trim().toLowerCase(),
          'password': clave.text,
        },
      );

      if (!mounted) return;
      clave.clear();
      repetir.clear();
      aviso(context, 'Cuenta creada correctamente. Inicia sesión.');
      irLogin();
    } catch (e) {
      if (!mounted) return;
      if (e is ErrorApi && e.incierto) {
        setState(() => incierto = true);
      }
      aviso(
        context,
        incierto
            ? '$e La cuenta podría haberse creado. '
                'Comprueba si puedes iniciar sesión antes de repetir.'
            : '$e',
      );
    } finally {
      if (mounted) setState(() => ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final habilitado = !ocupado && !incierto;

    return PopScope(
      canPop: !ocupado,
      child: PaginaAcceso(
        titulo: 'Crea tu cuenta',
        descripcion:
            'Completa tus datos para comenzar en Smart Market Guayaquil.',
        child: Form(
          key: form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: nombre,
                  enabled: habilitado,
                  maxLength: 100,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(
                    labelText: 'Nombre completo',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? 'Escribe tu nombre completo'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: correo,
                  enabled: habilitado,
                  maxLength: 150,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  validator: validarCorreo,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                CampoPassword(
                  controller: clave,
                  enabled: habilitado,
                  nueva: true,
                  validator: validarPassword,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Mínimo 8 caracteres y máximo 72 bytes.',
                  style: TextStyle(color: gris, fontSize: 12),
                ),
                const SizedBox(height: 18),
                CampoPassword(
                  controller: repetir,
                  etiqueta: 'Confirmar contraseña',
                  enabled: habilitado,
                  nueva: true,
                  enviar: registrar,
                  validator: (v) => v != clave.text
                      ? 'Las contraseñas no coinciden'
                      : null,
                ),
                const SizedBox(height: 26),
                boton(
                  ocupado ? 'Creando cuenta...' : 'Crear cuenta',
                  habilitado ? registrar : null,
                  ocupado: ocupado,
                  icono: Icons.person_add_alt_1_rounded,
                ),
                const SizedBox(height: 14),
                TextButton(
                  onPressed: ocupado ? null : irLogin,
                  child: const Text('Ya tengo cuenta. Iniciar sesión'),
                ),
                if (incierto)
                  const BannerInfo(
                    titulo: 'Comprueba tu registro',
                    texto:
                        'No se confirmó el resultado. Intenta iniciar sesión '
                        'antes de registrarte nuevamente.',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== RECUPERACIÓN ====================

class RecuperarPage extends StatefulWidget {
  final String correoInicial;
  const RecuperarPage({super.key, this.correoInicial = ''});

  @override
  State<RecuperarPage> createState() => _RecuperarPageState();
}

class _RecuperarPageState extends State<RecuperarPage> {
  final form = GlobalKey<FormState>();
  final correo = TextEditingController();
  final enlace = TextEditingController();
  final clave = TextEditingController();
  final repetir = TextEditingController();

  bool ocupado = false;
  bool cambiar = false;
  bool enviado = false;
  bool incierto = false;

  @override
  void initState() {
    super.initState();
    correo.text = widget.correoInicial;
  }

  @override
  void dispose() {
    correo.dispose();
    enlace.dispose();
    clave.dispose();
    repetir.dispose();
    super.dispose();
  }

  void irLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LoginPage(correoInicial: correo.text.trim()),
      ),
    );
  }

  Future<void> procesar() async {
    if (ocupado || incierto || !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => ocupado = true);

    try {
      final resultado = await api(
        cambiar ? rutaCambiarPassword : rutaSolicitarRecuperacion,
        metodo: 'POST',
        datos: cambiar
            ? {
                'token': extraerToken(enlace.text),
                'password': clave.text,
              }
            : {'correo': correo.text.trim().toLowerCase()},
      );

      if (!mounted) return;

      if (cambiar) {
        clave.clear();
        repetir.clear();
        enlace.clear();
        aviso(
          context,
          resultado['mensaje']?.toString() ??
              'Contraseña actualizada. Inicia sesión.',
        );
        irLogin();
      } else {
        setState(() => enviado = true);
      }
    } catch (e) {
      if (!mounted) return;
      if (e is ErrorApi && e.incierto) {
        setState(() => incierto = true);
      }

      aviso(
        context,
        incierto
            ? '$e Comprueba tu correo o intenta iniciar sesión '
                'antes de repetir.'
            : '$e',
      );
    } finally {
      if (mounted) setState(() => ocupado = false);
    }
  }

  void cambiarPaso() {
    FocusScope.of(context).unfocus();
    form.currentState?.reset();
    setState(() {
      cambiar = !cambiar;
      incierto = false;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !ocupado,
        child: PaginaAcceso(
          titulo: cambiar ? 'Nueva contraseña' : 'Recupera tu acceso',
          descripcion: cambiar
              ? 'Pega el enlace del correo o el token y escribe '
                  'tu nueva contraseña.'
              : 'Escribe el correo electrónico asociado a tu cuenta.',
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!cambiar)
                  TextFormField(
                    controller: correo,
                    enabled: !ocupado && !incierto && !enviado,
                    maxLength: 150,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    validator: validarCorreo,
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                  ),
                if (cambiar) ...[
                  const BannerInfo(
                    titulo: 'Enlace de un solo uso',
                    texto:
                        'El enlace vence en 30 minutos. Puedes pegarlo '
                        'completo aquí sin abrir la página web.',
                    icono: Icons.timer_outlined,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: enlace,
                    enabled: !ocupado && !incierto,
                    autocorrect: false,
                    enableSuggestions: false,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Enlace o token de recuperación',
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.link_rounded),
                    ),
                    validator: (v) =>
                        RegExp(r'^[a-f0-9]{64}$')
                                .hasMatch(extraerToken(v ?? ''))
                            ? null
                            : 'Pega el enlace completo o el token válido',
                  ),
                  const SizedBox(height: 18),
                  CampoPassword(
                    controller: clave,
                    enabled: !ocupado && !incierto,
                    etiqueta: 'Nueva contraseña',
                    nueva: true,
                    validator: validarPassword,
                  ),
                  const SizedBox(height: 18),
                  CampoPassword(
                    controller: repetir,
                    enabled: !ocupado && !incierto,
                    etiqueta: 'Confirmar contraseña',
                    nueva: true,
                    enviar: procesar,
                    validator: (v) => v != clave.text
                        ? 'Las contraseñas no coinciden'
                        : null,
                  ),
                ],
                const SizedBox(height: 24),
                if (enviado && !cambiar)
                  const BannerInfo(
                    icono: Icons.mark_email_read_outlined,
                    titulo: 'Solicitud procesada',
                    texto:
                        'Si el correo está registrado, recibirás instrucciones. '
                        'Revisa también spam. Después copia el enlace del '
                        'correo y pulsa “Ya tengo el enlace”.',
                  )
                else
                  boton(
                    ocupado
                        ? 'Procesando...'
                        : cambiar
                            ? 'Guardar contraseña'
                            : 'Solicitar recuperación',
                    incierto ? null : procesar,
                    ocupado: ocupado,
                    icono: Icons.lock_reset_rounded,
                  ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: ocupado ? null : cambiarPaso,
                  child: Text(
                    cambiar
                        ? 'Volver a solicitar recuperación'
                        : 'Ya tengo el enlace',
                  ),
                ),
                TextButton(
                  onPressed: ocupado ? null : irLogin,
                  child: const Text('Volver al inicio de sesión'),
                ),
              ],
            ),
          ),
        ),
      );
}

// ==================== MENÚ ====================

class MenuPage extends StatelessWidget {
  final String token;
  final Map<String, dynamic> usuario;

  const MenuPage({
    super.key,
    required this.token,
    required this.usuario,
  });

  @override
  Widget build(BuildContext context) {
    void abrir(Widget pagina) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => pagina),
      );
    }

    Future<void> salir() async {
      final ok = await confirmar(
        context,
        'Cerrar sesión',
        '¿Deseas salir de tu cuenta?',
      );
      if (!ok || !context.mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const InicioPage()),
        (_) => false,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SMART MARKET'),
            Text(
              'GUAYAQUIL',
              style: TextStyle(
                color: verde,
                fontSize: 11,
                letterSpacing: 3,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: salir,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [azul, verde]),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.waving_hand_rounded,
                      color: Color(0xFFFFD67D),
                      size: 30,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '¡Hola, ${usuario['nombre'] ?? 'Usuario'}!',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Todo listo para gestionar tu negocio.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Rol: ${usuario['rol'] ?? 'Usuario'}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const BannerInfo(
                titulo: 'Comienza con el resumen del día',
                texto:
                    'Consulta tus ventas y revisa los productos '
                    'con existencias bajas.',
                icono: Icons.insights_rounded,
              ),
              const SizedBox(height: 26),
              const Text(
                '¿Qué deseas hacer?',
                style: TextStyle(
                  color: azul,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              Modulo(
                titulo: 'Resumen del día',
                texto: 'Ventas e indicadores de tu negocio',
                icono: Icons.dashboard_outlined,
                color: verde,
                accion: () => abrir(ResumenPage(token: token)),
              ),
              Modulo(
                titulo: 'Productos',
                texto: 'Consulta y administra tu catálogo',
                icono: Icons.inventory_2_outlined,
                color: const Color(0xFF3266A8),
                accion: () => abrir(
                  CatalogoPage(token: token, clientes: false),
                ),
              ),
              Modulo(
                titulo: 'Inventario',
                texto: 'Existencias, entradas y salidas',
                icono: Icons.warehouse_outlined,
                color: const Color(0xFFA16A15),
                accion: () => abrir(InventarioPage(token: token)),
              ),
              Modulo(
                titulo: 'Clientes',
                texto: 'Organiza los datos de tus clientes',
                icono: Icons.people_alt_outlined,
                color: const Color(0xFF7954A4),
                accion: () => abrir(
                  CatalogoPage(token: token, clientes: true),
                ),
              ),
              Modulo(
                titulo: 'Ventas',
                texto: 'Registra ventas y consulta su detalle',
                icono: Icons.point_of_sale_rounded,
                color: verde,
                accion: () => abrir(VentasPage(token: token)),
              ),
              Modulo(
                titulo: 'Historial de inventario',
                texto: 'Movimientos, fechas y responsables',
                icono: Icons.history_rounded,
                color: gris,
                accion: () => abrir(HistorialPage(token: token)),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: salir,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Cerrar sesión'),
              ),
              const SizedBox(height: 26),
            ],
          ),
        ),
      ),
    );
  }
}

class Modulo extends StatelessWidget {
  final String titulo;
  final String texto;
  final IconData icono;
  final Color color;
  final VoidCallback accion;

  const Modulo({
    super.key,
    required this.titulo,
    required this.texto,
    required this.icono,
    required this.color,
    required this.accion,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: borde),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: accion,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: color.withAlpha(22),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icono, color: color, size: 29),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          style: const TextStyle(
                            color: azul,
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          texto,
                          style: const TextStyle(
                            color: gris,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: gris),
                ],
              ),
            ),
          ),
        ),
      );
}

// ==================== PRODUCTOS / CLIENTES ====================

class CatalogoPage extends StatefulWidget {
  final String token;
  final bool clientes;

  const CatalogoPage({
    super.key,
    required this.token,
    required this.clientes,
  });

  @override
  State<CatalogoPage> createState() => _CatalogoPageState();
}

class _CatalogoPageState extends State<CatalogoPage> {
  List<Map<String, dynamic>> registros = [];
  bool cargando = true;
  bool ocupado = false;
  String? error;
  String busqueda = '';

  String get ruta => widget.clientes ? '/clientes' : '/productos';
  String get titulo => widget.clientes ? 'Clientes' : 'Productos';

  @override
  void initState() {
    super.initState();
    cargar();
  }

  Future<void> cargar() async {
    setState(() {
      cargando = true;
      error = null;
    });
    try {
      final d = await api(ruta, token: widget.token);
      final rs = lista(d[widget.clientes ? 'clientes' : 'productos']);
      if (mounted) setState(() => registros = rs);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  Future<void> formulario([Map<String, dynamic>? registro]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FormularioPage(
          token: widget.token,
          clientes: widget.clientes,
          registro: registro,
        ),
      ),
    );
    if (mounted) await cargar();
  }

  Future<void> desactivar(Map<String, dynamic> registro) async {
    if (ocupado) return;
    final ok = await confirmar(
      context,
      'Desactivar registro',
      '¿Deseas desactivar ${registro['nombre']}?',
    );
    if (!ok || !mounted) return;

    setState(() => ocupado = true);
    try {
      final d = await api(
        '$ruta/${registro['id']}/desactivar',
        token: widget.token,
        metodo: 'PATCH',
      );
      if (mounted) {
        aviso(context, '${d['mensaje'] ?? 'Registro desactivado'}');
      }
    } catch (e) {
      if (mounted) {
        aviso(context, '$e Comprueba la lista antes de repetir.');
      }
    } finally {
      if (mounted) {
        setState(() => ocupado = false);
        await cargar();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibles = registros.where((r) {
      return [
        r['nombre'],
        r['descripcion'],
        r['identificacion'],
        r['telefono'],
        r['correo'],
      ].join(' ').toLowerCase().contains(busqueda.toLowerCase().trim());
    }).toList();

    return PopScope(
      canPop: !ocupado,
      child: Scaffold(
        appBar: AppBar(
          title: Text(titulo),
          actions: [
            IconButton(
              tooltip: 'Actualizar',
              onPressed: cargando || ocupado ? null : cargar,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: cargando
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? fallo(error!, cargar)
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          children: [
                            BannerInfo(
                              titulo: widget.clientes
                                  ? 'Conoce mejor a tus clientes'
                                  : 'Tu catálogo, organizado',
                              texto: widget.clientes
                                  ? 'Registra y consulta sus datos de contacto.'
                                  : 'Administra nombres, descripciones y precios.',
                              icono: widget.clientes
                                  ? Icons.people_alt_outlined
                                  : Icons.inventory_2_outlined,
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              onChanged: (v) =>
                                  setState(() => busqueda = v),
                              decoration: InputDecoration(
                                labelText: 'Buscar ${titulo.toLowerCase()}',
                                prefixIcon: const Icon(Icons.search),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: visibles.isEmpty
                            ? vacio(
                                busqueda.trim().isEmpty
                                    ? 'No hay registros. Pulsa + para crear uno.'
                                    : 'No hay resultados para esta búsqueda.',
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  18, 0, 18, 100,
                                ),
                                itemCount: visibles.length,
                                itemBuilder: (context, i) {
                                  final r = visibles[i];
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 12),
                                    child: Panel(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${r['nombre']}',
                                            style: const TextStyle(
                                              color: azul,
                                              fontSize: 19,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            widget.clientes
                                                ? 'Identificación: ${r['identificacion'] ?? '—'}\n'
                                                    'Teléfono: ${r['telefono'] ?? '—'}\n'
                                                    'Correo: ${r['correo'] ?? '—'}'
                                                : '\$${r['precio']}\n'
                                                    '${r['descripcion'] ?? ''}',
                                            style: const TextStyle(
                                              color: gris,
                                              height: 1.5,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 12,
                                            children: [
                                              TextButton.icon(
                                                onPressed: ocupado
                                                    ? null
                                                    : () => formulario(r),
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                ),
                                                label: const Text('Editar'),
                                              ),
                                              TextButton.icon(
                                                onPressed: ocupado
                                                    ? null
                                                    : () => desactivar(r),
                                                icon: const Icon(
                                                  Icons.remove_circle_outline,
                                                  color: Colors.red,
                                                ),
                                                label: const Text(
                                                  'Desactivar',
                                                  style: TextStyle(
                                                    color: Colors.red,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: cargando || ocupado ? null : () => formulario(),
          icon: const Icon(Icons.add),
          label: Text(
            widget.clientes ? 'Nuevo cliente' : 'Nuevo producto',
          ),
        ),
      ),
    );
  }
}

class FormularioPage extends StatefulWidget {
  final String token;
  final bool clientes;
  final Map<String, dynamic>? registro;

  const FormularioPage({
    super.key,
    required this.token,
    required this.clientes,
    this.registro,
  });

  @override
  State<FormularioPage> createState() => _FormularioPageState();
}

class _FormularioPageState extends State<FormularioPage> {
  final form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> controles;

  bool ocupado = false;
  bool incierto = false;
  bool finalizado = false;

  Map<String, String> get campos => widget.clientes
      ? {
          'nombre': 'Nombre completo',
          'identificacion': 'Identificación',
          'telefono': 'Teléfono',
          'correo': 'Correo electrónico',
          'direccion': 'Dirección',
        }
      : {
          'nombre': 'Nombre del producto',
          'descripcion': 'Descripción',
          'precio': 'Precio',
        };

  int limite(String campo) => {
        'nombre': 150,
        'identificacion': 20,
        'telefono': 30,
        'correo': 150,
        'direccion': 250,
        'descripcion': 1000,
        'precio': 13,
      }[campo]!;

  @override
  void initState() {
    super.initState();
    controles = {
      for (final campo in campos.keys)
        campo: TextEditingController(
          text: '${widget.registro?[campo] ?? ''}',
        ),
    };
  }

  @override
  void dispose() {
    for (final c in controles.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> guardar() async {
    if (ocupado ||
        incierto ||
        finalizado ||
        !form.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => ocupado = true);

    try {
      final ruta = widget.clientes ? '/clientes' : '/productos';
      final datos = <String, dynamic>{
        for (final e in controles.entries)
          e.key: e.value.text.trim(),
      };
      if (datos.containsKey('precio')) {
        datos['precio'] =
            datos['precio'].toString().replaceAll(',', '.');
      }

      await api(
        widget.registro == null
            ? ruta
            : '$ruta/${widget.registro!['id']}',
        token: widget.token,
        metodo: widget.registro == null ? 'POST' : 'PUT',
        datos: datos,
      );

      if (!mounted) return;
      setState(() => finalizado = true);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      if (e is ErrorApi && e.incierto) {
        setState(() => incierto = true);
      }
      aviso(
        context,
        incierto ? '$e Vuelve a la lista y comprueba el resultado.' : '$e',
      );
    } finally {
      if (mounted) setState(() => ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !ocupado,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              '${widget.registro == null ? 'Crear' : 'Editar'} '
              '${widget.clientes ? 'cliente' : 'producto'}',
            ),
          ),
          body: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...campos.entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: TextFormField(
                            controller: controles[e.key],
                            enabled:
                                !ocupado && !incierto && !finalizado,
                            maxLength: limite(e.key),
                            maxLines: e.key == 'descripcion' ? 3 : 1,
                            keyboardType: e.key == 'precio'
                                ? const TextInputType.numberWithOptions(
                                    decimal: true,
                                  )
                                : e.key == 'correo'
                                    ? TextInputType.emailAddress
                                    : e.key == 'telefono'
                                        ? TextInputType.phone
                                        : TextInputType.text,
                            decoration: InputDecoration(labelText: e.value),
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (e.key == 'nombre' && s.isEmpty) {
                                return 'Escribe el nombre';
                              }
                              if (e.key == 'precio' &&
                                  !RegExp(r'^\d{1,10}([.,]\d{1,2})?$')
                                      .hasMatch(s)) {
                                return 'Precio válido con hasta 2 decimales';
                              }
                              if (e.key == 'correo' &&
                                  s.isNotEmpty &&
                                  !correoValido(s)) {
                                return 'Revisa el correo';
                              }
                              return null;
                            },
                          ),
                        ),
                      ),
                      boton(
                        ocupado ? 'Guardando...' : 'Guardar',
                        incierto || finalizado ? null : guardar,
                        ocupado: ocupado,
                        icono: Icons.save_outlined,
                      ),
                      if (incierto)
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Volver y comprobar la lista'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

// ==================== INVENTARIO ====================

class InventarioPage extends StatefulWidget {
  final String token;
  const InventarioPage({super.key, required this.token});

  @override
  State<InventarioPage> createState() => _InventarioPageState();
}

class _InventarioPageState extends State<InventarioPage> {
  List<Map<String, dynamic>> registros = [];
  bool cargando = true;
  String? error;

  @override
  void initState() {
    super.initState();
    cargar();
  }

  Future<void> cargar() async {
    setState(() {
      cargando = true;
      error = null;
    });
    try {
      final d = await api('/inventario', token: widget.token);
      final rs = lista(d['inventario']);
      if (mounted) setState(() => registros = rs);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Inventario'),
          actions: [
            IconButton(
              tooltip: 'Actualizar',
              onPressed: cargando ? null : cargar,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: cargando
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? fallo(error!, cargar)
                : registros.isEmpty
                    ? vacio('Primero registra productos en tu catálogo.')
                    : ListView(
                        padding: const EdgeInsets.all(18),
                        children: [
                          const BannerInfo(
                            titulo: 'Control de existencias',
                            texto:
                                'Selecciona un producto para registrar '
                                'una entrada o una salida.',
                            icono: Icons.warehouse_outlined,
                          ),
                          const SizedBox(height: 18),
                          ...registros.map((r) {
                            final stock = numero(r['existencia']);
                            final color = stock == 0
                                ? Colors.red
                                : stock <= 5
                                    ? Colors.orange
                                    : verde;
                            final estado = stock == 0
                                ? 'Sin existencias'
                                : stock <= 5
                                    ? 'Stock bajo'
                                    : 'Disponible';

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                leading: Icon(
                                  Icons.inventory_2_outlined,
                                  color: color,
                                  size: 32,
                                ),
                                title: Text(
                                  '${r['nombre']}',
                                  style: const TextStyle(
                                    color: azul,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  'Existencias: $stock\n$estado',
                                  style: TextStyle(color: color, height: 1.5),
                                ),
                                isThreeLine: true,
                                trailing: const Icon(Icons.swap_vert_rounded),
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => MovimientoPage(
                                        token: widget.token,
                                        producto: r,
                                      ),
                                    ),
                                  );
                                  if (mounted) await cargar();
                                },
                              ),
                            );
                          }),
                        ],
                      ),
      );
}

class MovimientoPage extends StatefulWidget {
  final String token;
  final Map<String, dynamic> producto;

  const MovimientoPage({
    super.key,
    required this.token,
    required this.producto,
  });

  @override
  State<MovimientoPage> createState() => _MovimientoPageState();
}

class _MovimientoPageState extends State<MovimientoPage> {
  final form = GlobalKey<FormState>();
  final cantidad = TextEditingController();
  final motivo = TextEditingController();

  String tipo = 'entrada';
  bool ocupado = false;
  bool incierto = false;
  bool finalizado = false;

  @override
  void dispose() {
    cantidad.dispose();
    motivo.dispose();
    super.dispose();
  }

  Future<void> guardar() async {
    if (ocupado ||
        incierto ||
        finalizado ||
        !form.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => ocupado = true);

    try {
      await api(
        '/inventario/movimientos',
        token: widget.token,
        metodo: 'POST',
        datos: {
          'producto_id': numero(widget.producto['producto_id']),
          'tipo': tipo,
          'cantidad': int.parse(cantidad.text.trim()),
          'motivo': motivo.text.trim(),
        },
      );

      if (!mounted) return;
      setState(() => finalizado = true);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      if (e is ErrorApi && e.incierto) {
        setState(() => incierto = true);
      }
      aviso(
        context,
        incierto ? '$e Comprueba el inventario antes de repetir.' : '$e',
      );
    } finally {
      if (mounted) setState(() => ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final habilitado = !ocupado && !incierto && !finalizado;

    return PopScope(
      canPop: !ocupado,
      child: Scaffold(
        appBar: AppBar(title: const Text('Movimiento de inventario')),
        body: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              BannerInfo(
                titulo: '${widget.producto['nombre']}',
                texto:
                    'Existencias al abrir: ${widget.producto['existencia']}',
                icono: Icons.inventory_2_outlined,
              ),
              const SizedBox(height: 20),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: tipo,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de movimiento',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'entrada',
                          child: Text('Entrada de productos'),
                        ),
                        DropdownMenuItem(
                          value: 'salida',
                          child: Text('Salida de productos'),
                        ),
                      ],
                      onChanged: habilitado
                          ? (v) => setState(() => tipo = v!)
                          : null,
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: cantidad,
                      enabled: habilitado,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Cantidad',
                        prefixIcon: Icon(Icons.numbers_rounded),
                      ),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        return n == null || n < 1 || n > 2147483647
                            ? 'Ingresa una cantidad entera positiva'
                            : null;
                      },
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: motivo,
                      enabled: habilitado,
                      maxLength: 250,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Motivo del movimiento',
                        alignLabelWithHint: true,
                      ),
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Escribe el motivo'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    boton(
                      ocupado ? 'Guardando...' : 'Guardar movimiento',
                      habilitado ? guardar : null,
                      ocupado: ocupado,
                      icono: Icons.save_outlined,
                    ),
                    if (incierto)
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Volver y comprobar inventario'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== FILTROS ====================

class FiltrosFechas extends StatelessWidget {
  final TextEditingController busqueda;
  final DateTime? desde;
  final DateTime? hasta;
  final VoidCallback aplicar;
  final VoidCallback limpiar;
  final ValueChanged<DateTime?> cambiarDesde;
  final ValueChanged<DateTime?> cambiarHasta;
  final bool ocupado;
  final String etiqueta;

  const FiltrosFechas({
    super.key,
    required this.busqueda,
    required this.desde,
    required this.hasta,
    required this.aplicar,
    required this.limpiar,
    required this.cambiarDesde,
    required this.cambiarHasta,
    required this.ocupado,
    required this.etiqueta,
  });

  Future<void> elegir(BuildContext context, bool inicial) async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: (inicial ? desde : hasta) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: inicial ? 'Fecha inicial' : 'Fecha final',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );

    if (fecha != null) {
      if (inicial) {
        cambiarDesde(fecha);
      } else {
        cambiarHasta(fecha);
      }
    }
  }

  String texto(DateTime? fecha) => fecha == null
      ? 'Sin fecha'
      : '${fecha.day}/${fecha.month}/${fecha.year}';

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: busqueda,
              enabled: !ocupado,
              maxLength: 150,
              onSubmitted: (_) {
                if (!ocupado) aplicar();
              },
              decoration: InputDecoration(
                labelText: etiqueta,
                prefixIcon: const Icon(Icons.search),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed:
                      ocupado ? null : () => elegir(context, true),
                  child: Text('Desde: ${texto(desde)}'),
                ),
                OutlinedButton(
                  onPressed:
                      ocupado ? null : () => elegir(context, false),
                  child: Text('Hasta: ${texto(hasta)}'),
                ),
                FilledButton(
                  onPressed: ocupado ? null : aplicar,
                  child: const Text('Buscar'),
                ),
                TextButton(
                  onPressed: ocupado ? null : limpiar,
                  child: const Text('Limpiar'),
                ),
              ],
            ),
          ],
        ),
      );
}

// ==================== VENTAS ====================

class VentasPage extends StatefulWidget {
  final String token;
  const VentasPage({super.key, required this.token});

  @override
  State<VentasPage> createState() => _VentasPageState();
}

class _VentasPageState extends State<VentasPage> {
  final busqueda = TextEditingController();
  DateTime? desde;
  DateTime? hasta;
  List<Map<String, dynamic>> ventas = [];

  bool cargando = true;
  bool anulando = false;
  bool abriendoDetalle = false;
  String? error;

  @override
  void initState() {
    super.initState();
    cargar();
  }

  @override
  void dispose() {
    busqueda.dispose();
    super.dispose();
  }

  Future<void> cargar() async {
    if (desde != null && hasta != null && desde!.isAfter(hasta!)) {
      aviso(context, 'Revisa el intervalo de fechas.');
      return;
    }

    setState(() {
      cargando = true;
      error = null;
    });

    try {
      final d = await api(
        consultaFiltros('/ventas', busqueda.text, desde, hasta),
        token: widget.token,
      );
      final rs = lista(d['ventas']);
      if (mounted) setState(() => ventas = rs);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  Future<void> detalle(Map<String, dynamic> registro) async {
    if (abriendoDetalle || anulando) return;
    setState(() => abriendoDetalle = true);

    try {
      final d = await api(
        '/ventas/${registro['id']}',
        token: widget.token,
      );
      final venta = Map<String, dynamic>.from(d['venta'] as Map);
      final lineas = lista(d['detalle']);
      if (!mounted) return;

      final anular = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Venta #${registro['id']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cliente: ${venta['cliente_nombre']}'),
                Text('Estado: ${venta['estado']}'),
                const SizedBox(height: 16),
                ...lineas.map(
                  (l) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(
                      '${l['nombre_producto']}\n'
                      '${l['cantidad']} × \$${l['precio_unitario']} '
                      '= \$${l['subtotal']}',
                    ),
                  ),
                ),
                const Divider(),
                Text(
                  'Total: \$${venta['total'] ?? registro['total']}',
                  style: const TextStyle(
                    color: azul,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (venta['estado'] == 'registrada')
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text(
                  'Anular venta',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );

      if (anular == true && mounted) {
        await anularVenta(registro);
      }
    } catch (e) {
      if (mounted) aviso(context, '$e');
    } finally {
      if (mounted) setState(() => abriendoDetalle = false);
    }
  }

  Future<void> anularVenta(Map<String, dynamic> venta) async {
    if (anulando) return;

    final ok = await confirmar(
      context,
      'Anular venta #${venta['id']}',
      'Las cantidades volverán al inventario y se conservará '
          'el historial de la venta.',
    );
    if (!ok || !mounted) return;

    setState(() => anulando = true);
    try {
      final d = await api(
        '/ventas/${venta['id']}/anular',
        token: widget.token,
        metodo: 'PATCH',
      );
      if (mounted) {
        aviso(context, '${d['mensaje'] ?? 'Venta anulada'}');
      }
    } catch (e) {
      if (mounted) {
        aviso(
          context,
          '$e Comprueba el estado de la venta antes de repetir.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => anulando = false);
        await cargar();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bloqueado = cargando || anulando || abriendoDetalle;

    return PopScope(
      canPop: !anulando,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ventas'),
          actions: [
            IconButton(
              tooltip: 'Actualizar',
              onPressed: bloqueado ? null : cargar,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            FiltrosFechas(
              busqueda: busqueda,
              desde: desde,
              hasta: hasta,
              aplicar: cargar,
              ocupado: bloqueado,
              etiqueta: 'Cliente o número de venta',
              cambiarDesde: (f) => setState(() => desde = f),
              cambiarHasta: (f) => setState(() => hasta = f),
              limpiar: () {
                busqueda.clear();
                setState(() {
                  desde = null;
                  hasta = null;
                });
                cargar();
              },
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Hasta 200 ventas · fechas de Ecuador',
                style: TextStyle(color: gris, fontSize: 12),
              ),
            ),
            Expanded(
              child: cargando || anulando
                  ? const Center(child: CircularProgressIndicator())
                  : error != null
                      ? fallo(error!, cargar)
                      : ventas.isEmpty
                          ? vacio(
                              'No hay ventas. Pulsa + para registrar una.',
                            )
                          : ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 100),
                              children: ventas.map((v) {
                                final anulada = v['estado'] == 'anulada';
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.all(16),
                                    leading: Icon(
                                      Icons.receipt_long_outlined,
                                      color: anulada ? Colors.red : verde,
                                    ),
                                    title: Text(
                                      'Venta #${v['id']}',
                                      style: const TextStyle(
                                        color: azul,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${v['cliente_nombre']}\n'
                                      '${v['estado']} · '
                                      '${fechaLocal(v['fecha_creacion'])}',
                                    ),
                                    isThreeLine: true,
                                    trailing: Text(
                                      '\$${v['total']}',
                                      style: const TextStyle(
                                        color: azul,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    onTap: bloqueado
                                        ? null
                                        : () => detalle(v),
                                  ),
                                );
                              }).toList(),
                            ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: bloqueado
              ? null
              : () async {
                  final resultado = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          NuevaVentaPage(token: widget.token),
                    ),
                  );
                  if (!mounted) return;
                  await cargar();
                  if (resultado == true && mounted) {
                    aviso(
                      context,
                      'Venta registrada. Inventario actualizado.',
                    );
                  }
                },
          icon: const Icon(Icons.add),
          label: const Text('Nueva venta'),
        ),
      ),
    );
  }
}

// ==================== NUEVA VENTA ====================

class NuevaVentaPage extends StatefulWidget {
  final String token;
  const NuevaVentaPage({super.key, required this.token});

  @override
  State<NuevaVentaPage> createState() => _NuevaVentaPageState();
}

class _NuevaVentaPageState extends State<NuevaVentaPage> {
  List<Map<String, dynamic>> clientes = [];
  List<Map<String, dynamic>> productos = [];
  final cantidades = <int, int>{};
  final observacion = TextEditingController();

  int? clienteId;
  bool cargando = true;
  bool ocupado = false;
  bool confirmando = false;
  bool incierto = false;
  bool finalizado = false;
  String? error;

  int get total => productos.fold<int>(
        0,
        (s, p) =>
            s +
            centavos(p['precio']) *
                (cantidades[numero(p['id'])] ?? 0),
      );

  @override
  void initState() {
    super.initState();
    cargar();
  }

  @override
  void dispose() {
    observacion.dispose();
    super.dispose();
  }

  Future<void> cargar() async {
    setState(() {
      cargando = true;
      error = null;
    });
    try {
      final d = await Future.wait([
        api('/clientes', token: widget.token),
        api('/productos', token: widget.token),
        api('/inventario', token: widget.token),
      ]);

      final cs = lista(d[0]['clientes']);
      final ps = lista(d[1]['productos']);
      final stock = {
        for (final r in lista(d[2]['inventario']))
          numero(r['producto_id']): numero(r['existencia']),
      };

      for (final p in ps) {
        centavos(p['precio']);
        p['existencia'] = stock[numero(p['id'])] ?? 0;
      }

      if (mounted) {
        setState(() {
          clientes = cs;
          productos = ps;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  Future<void> elegir(Map<String, dynamic> producto) async {
    final id = numero(producto['id']);
    final cantidad = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => CantidadPage(
          nombre: '${producto['nombre']}',
          stock: numero(producto['existencia']),
          inicial: cantidades[id] ?? 1,
        ),
      ),
    );
    if (mounted && cantidad != null) {
      setState(() => cantidades[id] = cantidad);
    }
  }

  Future<void> guardar() async {
    if (ocupado || confirmando || incierto || finalizado) return;
    if (clienteId == null || cantidades.isEmpty) {
      aviso(context, 'Selecciona un cliente y agrega productos.');
      return;
    }
    if (cantidades.length > 100) {
      aviso(context, 'La venta admite hasta 100 productos diferentes.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => confirmando = true);

    final ok = await confirmar(
      context,
      'Confirmar venta',
      'Total estimado: \$${dinero(total)}.\n\n'
          'El servidor verificará los precios actuales y descontará '
          'las existencias disponibles.',
    );

    if (!mounted) return;
    setState(() => confirmando = false);
    if (!ok) return;
    setState(() => ocupado = true);

    try {
      await api(
        '/ventas',
        token: widget.token,
        metodo: 'POST',
        datos: {
          'cliente_id': clienteId,
          'observacion': observacion.text.trim(),
          'productos': cantidades.entries
              .map(
                (e) => {
                  'producto_id': e.key,
                  'cantidad': e.value,
                },
              )
              .toList(),
        },
      );

      if (!mounted) return;
      setState(() => finalizado = true);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      if (e is ErrorApi && e.incierto) {
        setState(() => incierto = true);
      }
      aviso(
        context,
        incierto ? '$e Comprueba la lista de ventas antes de repetir.' : '$e',
      );
    } finally {
      if (mounted) setState(() => ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !ocupado && !confirmando,
        child: Scaffold(
          appBar: AppBar(title: const Text('Nueva venta')),
          body: cargando
              ? const Center(child: CircularProgressIndicator())
              : error != null
                  ? fallo(error!, cargar)
                  : AbsorbPointer(
                      absorbing: ocupado ||
                          confirmando ||
                          incierto ||
                          finalizado,
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          const BannerInfo(
                            titulo: 'Registra una venta',
                            texto:
                                'Selecciona el cliente y toca los productos '
                                'para indicar sus cantidades.',
                            icono: Icons.point_of_sale_rounded,
                          ),
                          const SizedBox(height: 20),
                          if (clientes.isEmpty) ...[
                            const Text(
                              'Primero registra un cliente '
                              'en el módulo Clientes.',
                              style: TextStyle(color: Colors.red),
                            ),
                            const SizedBox(height: 12),
                          ],
                          DropdownButtonFormField<int>(
                            initialValue: clienteId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Selecciona un cliente',
                              prefixIcon:
                                  Icon(Icons.person_outline_rounded),
                            ),
                            items: clientes
                                .map(
                                  (c) => DropdownMenuItem<int>(
                                    value: numero(c['id']),
                                    child: Text(
                                      '${c['nombre']}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => clienteId = v),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Productos disponibles',
                            style: TextStyle(
                              color: azul,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (productos.isEmpty)
                            const Text('No hay productos registrados.'),
                          ...productos.map((p) {
                            final id = numero(p['id']);
                            final n = cantidades[id] ?? 0;
                            final stock = numero(p['existencia']);

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                title: Text(
                                  '${p['nombre']}',
                                  style: const TextStyle(
                                    color: azul,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  'Precio: \$${p['precio']} · Stock: $stock\n'
                                  'Cantidad: $n · Subtotal: '
                                  '\$${dinero(centavos(p['precio']) * n)}',
                                ),
                                isThreeLine: true,
                                onTap: stock > 0 ? () => elegir(p) : null,
                                trailing: n > 0
                                    ? IconButton(
                                        tooltip: 'Quitar producto',
                                        onPressed: () => setState(
                                          () => cantidades.remove(id),
                                        ),
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                          color: Colors.red,
                                        ),
                                      )
                                    : Icon(
                                        stock > 0
                                            ? Icons.add_circle_outline
                                            : Icons.block,
                                        color: stock > 0 ? verde : gris,
                                      ),
                              ),
                            );
                          }),
                          const SizedBox(height: 18),
                          TextField(
                            controller: observacion,
                            maxLength: 250,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Observación (opcional)',
                              alignLabelWithHint: true,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Panel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'TOTAL ESTIMADO',
                                  style: TextStyle(
                                    color: gris,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '\$${dinero(total)}',
                                  style: const TextStyle(
                                    color: azul,
                                    fontSize: 34,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                boton(
                                  ocupado ? 'Guardando...' : 'Guardar venta',
                                  clienteId == null || cantidades.isEmpty
                                      ? null
                                      : guardar,
                                  ocupado: ocupado,
                                  icono: Icons.check_circle_outline,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
          bottomNavigationBar: incierto
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: boton(
                      'Volver y comprobar ventas',
                      () => Navigator.pop(context, false),
                      icono: Icons.receipt_long_outlined,
                    ),
                  ),
                )
              : null,
        ),
      );
}

class CantidadPage extends StatefulWidget {
  final String nombre;
  final int stock;
  final int inicial;

  const CantidadPage({
    super.key,
    required this.nombre,
    required this.stock,
    required this.inicial,
  });

  @override
  State<CantidadPage> createState() => _CantidadPageState();
}

class _CantidadPageState extends State<CantidadPage> {
  final form = GlobalKey<FormState>();
  late final TextEditingController cantidad;

  @override
  void initState() {
    super.initState();
    cantidad = TextEditingController(text: '${widget.inicial}');
  }

  @override
  void dispose() {
    cantidad.dispose();
    super.dispose();
  }

  void agregar() {
    if (form.currentState!.validate()) {
      Navigator.pop(context, int.parse(cantidad.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Cantidad del producto')),
        body: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              BannerInfo(
                titulo: widget.nombre,
                texto: 'Existencias disponibles: ${widget.stock}',
                icono: Icons.inventory_2_outlined,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: cantidad,
                autofocus: true,
                keyboardType: TextInputType.number,
                onFieldSubmitted: (_) => agregar(),
                decoration: const InputDecoration(
                  labelText: 'Cantidad',
                  prefixIcon: Icon(Icons.numbers_rounded),
                ),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  return n == null || n < 1 || n > widget.stock
                      ? 'Ingresa entre 1 y ${widget.stock}'
                      : null;
                },
              ),
              const SizedBox(height: 22),
              boton(
                'Agregar a la venta',
                agregar,
                icono: Icons.add_shopping_cart_rounded,
              ),
            ],
          ),
        ),
      );
}

// ==================== RESUMEN ====================

class ResumenPage extends StatefulWidget {
  final String token;
  const ResumenPage({super.key, required this.token});

  @override
  State<ResumenPage> createState() => _ResumenPageState();
}

class _ResumenPageState extends State<ResumenPage> {
  Map<String, dynamic>? datos;
  bool cargando = true;
  String? error;

  @override
  void initState() {
    super.initState();
    cargar();
  }

  Future<void> cargar() async {
    setState(() {
      cargando = true;
      error = null;
    });
    try {
      final d = await api('/resumen', token: widget.token);
      final resumen = Map<String, dynamic>.from(d['resumen'] as Map);
      if (mounted) setState(() => datos = resumen);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Resumen del día'),
          actions: [
            IconButton(
              tooltip: 'Actualizar',
              onPressed: cargando ? null : cargar,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: cargando
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? fallo(error!, cargar)
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      const BannerInfo(
                        titulo: 'Así va tu negocio hoy',
                        texto:
                            'Datos del servidor según la hora de Ecuador. '
                            'Las ventas anuladas se excluyen.',
                        icono: Icons.insights_rounded,
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [azul, verde],
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TOTAL VENDIDO HOY',
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '\$${datos!['total_hoy']}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 38,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '${datos!['ventas_hoy']} ventas registradas',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      ...{
                        'Clientes activos': '${datos!['clientes']}',
                        'Productos activos': '${datos!['productos']}',
                        'Productos sin existencias': '${datos!['sin_stock']}',
                        'Stock bajo (1 a 5 unidades)': '${datos!['stock_bajo']}',
                      }.entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Panel(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    e.key,
                                    style: const TextStyle(
                                      color: azul,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  e.value,
                                  style: const TextStyle(
                                    color: verde,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      boton(
                        'Revisar inventario',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                InventarioPage(token: widget.token),
                          ),
                        ),
                        icono: Icons.warehouse_outlined,
                      ),
                    ],
                  ),
      );
}

// ==================== HISTORIAL ====================

class HistorialPage extends StatefulWidget {
  final String token;
  const HistorialPage({super.key, required this.token});

  @override
  State<HistorialPage> createState() => _HistorialPageState();
}

class _HistorialPageState extends State<HistorialPage> {
  final busqueda = TextEditingController();
  DateTime? desde;
  DateTime? hasta;
  List<Map<String, dynamic>> registros = [];
  bool cargando = true;
  String? error;

  @override
  void initState() {
    super.initState();
    cargar();
  }

  @override
  void dispose() {
    busqueda.dispose();
    super.dispose();
  }

  Future<void> cargar() async {
    if (desde != null && hasta != null && desde!.isAfter(hasta!)) {
      aviso(context, 'Revisa el intervalo de fechas.');
      return;
    }

    setState(() {
      cargando = true;
      error = null;
    });

    try {
      final d = await api(
        consultaFiltros(
          '/inventario/historial',
          busqueda.text,
          desde,
          hasta,
        ),
        token: widget.token,
      );
      final rs = lista(d['movimientos']);
      if (mounted) setState(() => registros = rs);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Historial de inventario'),
          actions: [
            IconButton(
              tooltip: 'Actualizar',
              onPressed: cargando ? null : cargar,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            FiltrosFechas(
              busqueda: busqueda,
              desde: desde,
              hasta: hasta,
              aplicar: cargar,
              ocupado: cargando,
              etiqueta: 'Nombre del producto',
              cambiarDesde: (f) => setState(() => desde = f),
              cambiarHasta: (f) => setState(() => hasta = f),
              limpiar: () {
                busqueda.clear();
                setState(() {
                  desde = null;
                  hasta = null;
                });
                cargar();
              },
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Hasta 200 movimientos · fechas de Ecuador',
                style: TextStyle(color: gris, fontSize: 12),
              ),
            ),
            Expanded(
              child: cargando
                  ? const Center(child: CircularProgressIndicator())
                  : error != null
                      ? fallo(error!, cargar)
                      : registros.isEmpty
                          ? vacio('No hay movimientos con estos filtros.')
                          : ListView(
                              padding: const EdgeInsets.all(16),
                              children: registros.map((m) {
                                final entrada = m['tipo'] == 'entrada';

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.all(16),
                                    leading: Icon(
                                      entrada
                                          ? Icons.south_west_rounded
                                          : Icons.north_east_rounded,
                                      color: entrada ? verde : Colors.orange,
                                    ),
                                    title: Text(
                                      '${m['nombre']}',
                                      style: const TextStyle(
                                        color: azul,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        '${entrada ? 'Entrada' : 'Salida'}: '
                                        '${m['cantidad']} unidades\n'
                                        '${m['motivo']}\n'
                                        'Existencias: '
                                        '${m['existencia_anterior']} '
                                        '→ ${m['existencia_nueva']}\n'
                                        '${fechaLocal(m['fecha'])}\n'
                                        'Responsable: ${m['usuario_nombre']}',
                                        style: const TextStyle(
                                          color: gris,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
            ),
          ],
        ),
      );
}