import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const apiUrl = 'http://10.0.2.2:3000';

void main() => runApp(const GestionComercialApp());

class ErrorApi implements Exception {
  final String mensaje;
  final bool incierto;
  const ErrorApi(this.mensaje, {this.incierto = false});
  @override
  String toString() => mensaje;
}

Future<Map<String, dynamic>> api(String ruta, {
  String? token, String metodo = 'GET', Map<String, dynamic>? datos,
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
      case 'POST': peticion = http.post(uri, headers: headers, body: body); break;
      case 'PUT': peticion = http.put(uri, headers: headers, body: body); break;
      case 'PATCH': peticion = http.patch(uri, headers: headers, body: body); break;
      default: peticion = http.get(uri, headers: headers);
    }
    final r = await peticion.timeout(const Duration(seconds: 20));
    final d = jsonDecode(utf8.decode(r.bodyBytes));
    if (d is! Map<String, dynamic>) throw const FormatException();
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ErrorApi(
        r.statusCode == 401 ? 'Sesión vencida o credenciales incorrectas. Inicia sesión nuevamente.'
          : (d['mensaje']?.toString() ?? 'No se pudo completar la operación'),
        incierto: mutacion && r.statusCode >= 500,
      );
    }
    return d;
  } on ErrorApi { rethrow;
  } on TimeoutException {
    throw ErrorApi('El servidor tardó demasiado.', incierto: mutacion);
  } on FormatException {
    throw ErrorApi('Respuesta inesperada del servidor. Revisa index.js.', incierto: mutacion);
  } catch (_) {
    throw ErrorApi('No se pudo conectar. Revisa que el backend esté encendido.', incierto: mutacion);
  }
}

List<Map<String, dynamic>> lista(dynamic valor) => (valor as List)
  .map((e) => Map<String, dynamic>.from(e as Map)).toList();

void aviso(BuildContext context, String texto) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
}

Widget fallo(String texto, VoidCallback reintentar) => Center(
  child: Padding(padding: const EdgeInsets.all(24), child: Column(
    mainAxisSize: MainAxisSize.min, children: [
      Text(texto, textAlign: TextAlign.center),
      TextButton(onPressed: reintentar, child: const Text('Reintentar')),
    ],
  )),
);

Future<bool> confirmar(BuildContext context, String titulo, String texto) async =>
  await showDialog<bool>(context: context, builder: (c) => AlertDialog(
    title: Text(titulo), content: Text(texto), actions: [
      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmar')),
    ],
  )) ?? false;

class GestionComercialApp extends StatelessWidget {
  const GestionComercialApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false, title: 'Gestión Comercial',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue), useMaterial3: true),
    home: const InicioPage(),
  );
}

class InicioPage extends StatelessWidget {
  const InicioPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Gestión Comercial')),
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.store, size: 90, color: Colors.blue),
      const SizedBox(height: 20),
      const Text('SMARTMARKET-GUAYAQUIL', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 24),
      FilledButton(onPressed: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const LoginPage())), child: const Text('Ingresar')),
    ])),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final correo = TextEditingController();
  final clave = TextEditingController();
  bool ocupado = false;
  @override
  void dispose() { correo.dispose(); clave.dispose(); super.dispose(); }
  Future<void> ingresar() async {
    if (ocupado) return;
    if (correo.text.trim().isEmpty || clave.text.isEmpty) {
      aviso(context, 'Escribe tu correo y contraseña'); return;
    }
    FocusScope.of(context).unfocus();
    setState(() => ocupado = true);
    try {
      final d = await api('/login', metodo: 'POST', datos: {'correo': correo.text.trim(), 'password': clave.text});
      final token = d['token'];
      if (token is! String || token.isEmpty) throw const ErrorApi('El servidor no devolvió un token válido');
      final p = await api('/perfil', token: token);
      final u = Map<String, dynamic>.from(p['usuario'] as Map);
      if (!mounted) return;
      clave.clear();
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MenuPage(token: token, usuario: u)));
    } catch (e) { if (mounted) aviso(context, e.toString()); }
    finally { if (mounted) setState(() => ocupado = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Inicio de sesión')),
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(children: [
      const Icon(Icons.account_circle, size: 80, color: Colors.blue),
      const SizedBox(height: 24),
      TextField(controller: correo, enabled: !ocupado, keyboardType: TextInputType.emailAddress,
        autocorrect: false, decoration: const InputDecoration(labelText: 'Correo', border: OutlineInputBorder())),
      const SizedBox(height: 16),
      TextField(controller: clave, enabled: !ocupado, obscureText: true, enableSuggestions: false,
        onSubmitted: (_) => ingresar(), decoration: const InputDecoration(labelText: 'Contraseña', border: OutlineInputBorder())),
      const SizedBox(height: 24),
      FilledButton(onPressed: ocupado ? null : ingresar, child: Text(ocupado ? 'Ingresando...' : 'Iniciar sesión')),
    ]))),
  );
}

class MenuPage extends StatelessWidget {
  final String token;
  final Map<String, dynamic> usuario;
  const MenuPage({super.key, required this.token, required this.usuario});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SMARTMARKET-GUAYAQUIL')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text('Bienvenido, ${usuario['nombre']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      Text('Rol: ${usuario['rol']}'), const SizedBox(height: 24),
      ListTile(leading:const Icon(Icons.dashboard),title:const Text('Resumen del día'),trailing:const Icon(Icons.chevron_right),
        onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ResumenPage(token:token)))),
      ListTile(leading:const Icon(Icons.history),title:const Text('Historial de inventario'),trailing:const Icon(Icons.chevron_right),
        onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>HistorialPage(token:token)))),
      ListTile(leading: const Icon(Icons.inventory_2), title: const Text('Productos'), trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CatalogoPage(token: token, clientes: false)))),
      ListTile(leading: const Icon(Icons.warehouse), title: const Text('Inventario'), trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InventarioPage(token: token)))),
      ListTile(leading: const Icon(Icons.people), title: const Text('Clientes'), trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CatalogoPage(token: token, clientes: true)))),
      ListTile(leading: const Icon(Icons.shopping_cart), title: const Text('Ventas'), trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VentasPage(token: token)))),
      const SizedBox(height: 24),
      OutlinedButton(onPressed: () => Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const InicioPage()), (_) => false), child: const Text('Cerrar sesión')),
    ]),
  );
}

class CatalogoPage extends StatefulWidget {
  final String token;
  final bool clientes;
  const CatalogoPage({super.key, required this.token, required this.clientes});
  @override
  State<CatalogoPage> createState() => _CatalogoPageState();
}
class _CatalogoPageState extends State<CatalogoPage> {
  List<Map<String, dynamic>> registros = [];
  bool cargando = true, ocupado = false;
  String? error;
  String busqueda = '';
  String get ruta => widget.clientes ? '/clientes' : '/productos';
  String get titulo => widget.clientes ? 'Clientes' : 'Productos';
  @override
  void initState() { super.initState(); cargar(); }
  Future<void> cargar() async {
    setState(() { cargando = true; error = null; });
    try {
      final d = await api(ruta, token: widget.token);
      if (mounted) setState(() => registros = lista(d[widget.clientes ? 'clientes' : 'productos']));
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => cargando = false); }
  }
  Future<void> formulario([Map<String, dynamic>? registro]) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => FormularioPage(
      token: widget.token, clientes: widget.clientes, registro: registro)));
    if (mounted) await cargar();
  }
  Future<void> desactivar(Map<String, dynamic> r) async {
    if (ocupado) return;
    if (!await confirmar(context, 'Desactivar', '¿Desactivar ${r['nombre']}?')) return;
    if (!mounted) return;
    setState(() => ocupado = true);
    try {
      final d = await api('$ruta/${r['id']}/desactivar', token: widget.token, metodo: 'PATCH');
      if (mounted) aviso(context, d['mensaje'].toString());
    } catch (e) { if (mounted) aviso(context, '$e. Revisa la lista antes de repetir.'); }
    finally { if (mounted) { setState(() => ocupado = false); await cargar(); } }
  }
  @override
  Widget build(BuildContext context) {
    final visibles = registros.where((r) => [r['nombre'], r['identificacion'], r['telefono']]
      .join(' ').toLowerCase().contains(busqueda.toLowerCase())).toList();
    return PopScope(canPop: !ocupado, child: Scaffold(
      appBar: AppBar(title: Text(titulo), actions: [IconButton(onPressed: cargando || ocupado ? null : cargar, icon: const Icon(Icons.refresh))]),
      body: cargando ? const Center(child: CircularProgressIndicator()) : error != null ? fallo(error!, cargar)
        : Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: TextField(onChanged: (v) => setState(() => busqueda = v),
            decoration: const InputDecoration(labelText: 'Buscar', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()))),
          Expanded(child: visibles.isEmpty ? const Center(child: Text('No hay registros. Pulsa + para crear uno.'))
            : ListView.builder(padding: const EdgeInsets.only(bottom: 90), itemCount: visibles.length, itemBuilder: (context, i) {
              final r = visibles[i];
              return ListTile(title: Text(r['nombre'].toString()),
                subtitle: Text(widget.clientes ? '${r['identificacion'] ?? ''}\n${r['telefono'] ?? ''}' : '\$${r['precio']}\n${r['descripcion'] ?? ''}'),
                isThreeLine: true, trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(onPressed: ocupado ? null : () => formulario(r), icon: const Icon(Icons.edit)),
                  IconButton(onPressed: ocupado ? null : () => desactivar(r), icon: const Icon(Icons.remove_circle_outline, color: Colors.red)),
                ]));
            })),
        ]),
      floatingActionButton: FloatingActionButton(onPressed: cargando || ocupado ? null : () => formulario(), child: const Icon(Icons.add)),
    ));
  }
}

class FormularioPage extends StatefulWidget {
  final String token;
  final bool clientes;
  final Map<String, dynamic>? registro;
  const FormularioPage({super.key, required this.token, required this.clientes, this.registro});
  @override
  State<FormularioPage> createState() => _FormularioPageState();
}
class _FormularioPageState extends State<FormularioPage> {
  final form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> controles;
  bool ocupado = false, incierto = false, finalizado = false;
  Map<String, String> get campos => widget.clientes
    ? {'nombre': 'Nombre', 'identificacion': 'Identificación', 'telefono': 'Teléfono', 'correo': 'Correo', 'direccion': 'Dirección'}
    : {'nombre': 'Nombre', 'descripcion': 'Descripción', 'precio': 'Precio'};
  int limite(String k) => {'nombre': 150, 'identificacion': 20, 'telefono': 30, 'correo': 150, 'direccion': 250, 'descripcion': 1000, 'precio': 13}[k]!;
  @override
  void initState() {
    super.initState();
    controles = {for (final k in campos.keys) k: TextEditingController(text: widget.registro?[k]?.toString() ?? '')};
  }
  @override
  void dispose() { for (final c in controles.values) { c.dispose(); } super.dispose(); }
  Future<void> guardar() async {
    if (ocupado || incierto || finalizado || !form.currentState!.validate()) return;
    setState(() => ocupado = true);
    try {
      final ruta = widget.clientes ? '/clientes' : '/productos';
      final editando = widget.registro != null;
      await api(editando ? '$ruta/${widget.registro!['id']}' : ruta, token: widget.token,
        metodo: editando ? 'PUT' : 'POST', datos: {for (final e in controles.entries) e.key: e.value.text.trim()});
      if (!mounted) return;
      setState(() { ocupado = false; finalizado = true; });
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) Navigator.pop(context); });
    } catch (e) {
      if (!mounted) return;
      if (e is ErrorApi && e.incierto) setState(() => incierto = true);
      aviso(context, incierto ? '$e Vuelve a la lista y comprueba el resultado antes de repetir.' : e.toString());
    } finally { if (mounted) setState(() => ocupado = false); }
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !ocupado, child: Scaffold(
    appBar: AppBar(title: Text('${widget.registro == null ? 'Crear' : 'Editar'} ${widget.clientes ? 'cliente' : 'producto'}')),
    body: Form(key: form, child: ListView(padding: const EdgeInsets.all(24), children: [
      ...campos.entries.map((e) => Padding(padding: const EdgeInsets.only(bottom: 16), child: TextFormField(
        controller: controles[e.key], enabled: !ocupado && !incierto && !finalizado, maxLength: limite(e.key),
        keyboardType: e.key == 'precio' ? const TextInputType.numberWithOptions(decimal: true)
          : e.key == 'correo' ? TextInputType.emailAddress : TextInputType.text,
        decoration: InputDecoration(labelText: e.value, border: const OutlineInputBorder()),
        validator: (v) {
          final s = (v ?? '').trim();
          if (e.key == 'nombre' && s.isEmpty) return 'Escribe el nombre';
          if (e.key == 'precio' && !RegExp(r'^\d{1,10}([.,]\d{1,2})?$').hasMatch(s)) return 'Ingresa un precio válido con hasta 2 decimales';
          if (e.key == 'correo' && s.isNotEmpty && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s)) return 'Revisa el correo';
          return null;
        },
      ))),
      FilledButton(onPressed: ocupado || incierto || finalizado ? null : guardar, child: Text(ocupado ? 'Guardando...' : 'Guardar')),
      if (incierto) TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver y comprobar la lista')),
    ])),
  ));
}

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
  void initState() { super.initState(); cargar(); }
  Future<void> cargar() async {
    setState(() { cargando = true; error = null; });
    try {
      final d = await api('/inventario', token: widget.token);
      if (mounted) setState(() => registros = lista(d['inventario']));
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => cargando = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Inventario'), actions: [IconButton(onPressed: cargando ? null : cargar, icon: const Icon(Icons.refresh))]),
    body: cargando ? const Center(child: CircularProgressIndicator()) : error != null ? fallo(error!, cargar)
      : registros.isEmpty ? const Center(child: Text('Primero registra productos.'))
      : ListView(children: registros.map((r) => ListTile(title: Text(r['nombre'].toString()),
        subtitle: Text('Existencias: ${r['existencia']} · ${(r['existencia'] as int)==0?'SIN STOCK':(r['existencia'] as int)<=5?'STOCK BAJO':'Disponible'}'),
        leading:Icon(Icons.inventory_2,color:(r['existencia'] as int)==0?Colors.red:(r['existencia'] as int)<=5?Colors.orange:Colors.green),
        trailing: const Icon(Icons.swap_vert),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => MovimientoPage(token: widget.token, producto: r)));
          if (mounted) await cargar();
        })).toList()),
  );
}

class MovimientoPage extends StatefulWidget {
  final String token;
  final Map<String, dynamic> producto;
  const MovimientoPage({super.key, required this.token, required this.producto});
  @override
  State<MovimientoPage> createState() => _MovimientoPageState();
}
class _MovimientoPageState extends State<MovimientoPage> {
  final cantidad = TextEditingController();
  final motivo = TextEditingController();
  String tipo = 'entrada';
  bool ocupado = false, incierto = false, finalizado = false;
  @override
  void dispose() { cantidad.dispose(); motivo.dispose(); super.dispose(); }
  Future<void> guardar() async {
    if (ocupado || incierto || finalizado) return;
    final n = int.tryParse(cantidad.text.trim());
    if (n == null || n < 1 || n > 2147483647 || motivo.text.trim().isEmpty) {
      aviso(context, 'Ingresa una cantidad entera positiva y el motivo'); return;
    }
    setState(() => ocupado = true);
    try {
      await api('/inventario/movimientos', token: widget.token, metodo: 'POST', datos: {
        'producto_id': widget.producto['producto_id'], 'tipo': tipo, 'cantidad': n, 'motivo': motivo.text.trim(),
      });
      if (!mounted) return;
      setState(() { ocupado = false; finalizado = true; });
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) Navigator.pop(context); });
    } catch (e) {
      if (!mounted) return;
      if (e is ErrorApi && e.incierto) setState(() => incierto = true);
      aviso(context, incierto ? '$e Comprueba el inventario antes de repetir.' : e.toString());
    } finally { if (mounted) setState(() => ocupado = false); }
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !ocupado, child: Scaffold(
    appBar: AppBar(title: const Text('Movimiento de inventario')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      Text(widget.producto['nombre'].toString(), style: const TextStyle(fontSize: 22)),
      Text('Existencias al abrir: ${widget.producto['existencia']}'), const SizedBox(height: 20),
      DropdownButtonFormField<String>(initialValue: tipo, items: const [
        DropdownMenuItem(value: 'entrada', child: Text('Entrada')),
        DropdownMenuItem(value: 'salida', child: Text('Salida')),
      ], onChanged: ocupado || incierto || finalizado ? null : (v) => setState(() => tipo = v!), decoration: const InputDecoration(labelText: 'Tipo')),
      const SizedBox(height: 16),
      TextField(controller: cantidad, enabled: !ocupado && !incierto && !finalizado, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad')),
      TextField(controller: motivo, enabled: !ocupado && !incierto && !finalizado, maxLength: 250, decoration: const InputDecoration(labelText: 'Motivo')),
      FilledButton(onPressed: ocupado || incierto || finalizado ? null : guardar, child: Text(ocupado ? 'Guardando...' : 'Guardar movimiento')),
      if (incierto) TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver y comprobar inventario')),
    ]),
  ));
}

int centavos(dynamic precio) {
  final partes = precio.toString().split('.');
  return int.parse(partes[0]) * 100 + int.parse((partes.length > 1 ? partes[1] : '').padRight(2, '0').substring(0, 2));
}
String dinero(int n) => '${n ~/ 100}.${(n % 100).toString().padLeft(2, '0')}';

class VentasPage extends StatefulWidget {
  final String token;
  const VentasPage({super.key, required this.token});
  @override
  State<VentasPage> createState() => _VentasPageState();
}
class _VentasPageState extends State<VentasPage> {
  List<Map<String, dynamic>> ventas = [];
  bool cargando = true, anulando=false;
  final busqueda=TextEditingController();
  DateTime? desde,hasta;
  String? error;
  @override
  void initState() { super.initState(); cargar(); }
  @override
  void dispose(){busqueda.dispose();super.dispose();}
  Future<void> cargar() async {
    if(desde!=null&&hasta!=null&&desde!.isAfter(hasta!)){aviso(context,'Revisa el intervalo de fechas');return;}
    setState(() { cargando = true; error = null; });
    try {
      final d = await api(consultaFiltros('/ventas',busqueda.text,desde,hasta), token: widget.token);
      if (mounted) setState(() => ventas = lista(d['ventas']));
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => cargando = false); }
  }
  Future<void> detalle(Map<String, dynamic> v) async {
    try {
      final d = await api('/ventas/${v['id']}', token: widget.token);
      final lineas = lista(d['detalle']);
      final venta=Map<String,dynamic>.from(d['venta'] as Map);
      bool anular=false;
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (c) => AlertDialog(
        title: Text('Venta #${v['id']}'), content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Cliente: ${venta['cliente_nombre']}'), Text('Estado: ${venta['estado']}'), const SizedBox(height: 16),
            ...lineas.map((l) => Padding(padding: const EdgeInsets.only(bottom: 12), child:
              Text('${l['nombre_producto']}\n${l['cantidad']} × \$${l['precio_unitario']} = \$${l['subtotal']}'))),
            Text('Total: \$${v['total']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        )), actions: [
          if(venta['estado']=='registrada') TextButton(onPressed:(){anular=true;Navigator.pop(c);},child:const Text('Anular venta',style:TextStyle(color:Colors.red))),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar'))],
      ));
      if(anular&&mounted) await anularVenta(v);
    } catch (e) { if (mounted) aviso(context, e.toString()); }
  }
  Future<void> anularVenta(Map<String,dynamic> v)async{
    if(anulando)return;
    final ok=await confirmar(context,'Anular venta #${v['id']}','Se devolverán todas las cantidades al inventario. La venta conservará su historial.');
    if(!ok||!mounted)return;
    setState(()=>anulando=true);
    try{
      final d=await api('/ventas/${v['id']}/anular',token:widget.token,metodo:'PATCH');
      if(mounted)aviso(context,d['mensaje'].toString());
    }catch(e){if(mounted)aviso(context,'$e Revisa el estado de la venta.');}
    finally{if(mounted){setState(()=>anulando=false);await cargar();}}
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop:!anulando,child:Scaffold(
    appBar: AppBar(title: const Text('Ventas'), actions: [IconButton(onPressed: cargando || anulando ? null : cargar, icon: const Icon(Icons.refresh))]),
    body:Column(children:[
      FiltrosFechas(busqueda:busqueda,desde:desde,hasta:hasta,aplicar:cargar,ocupado:cargando||anulando,etiqueta:'Cliente o número de venta',
        cambiarDesde:(f)=>setState(()=>desde=f),cambiarHasta:(f)=>setState(()=>hasta=f),limpiar:(){busqueda.clear();setState((){desde=null;hasta=null;});cargar();}),
      const Text('Hasta 200 ventas · fechas de Ecuador'),
      Expanded(child: cargando || anulando ? const Center(child: CircularProgressIndicator()) : error != null ? fallo(error!, cargar)
      : ventas.isEmpty ? const Center(child: Text('No hay ventas. Pulsa + para registrar una.'))
      : ListView(padding: const EdgeInsets.only(bottom: 90), children: ventas.map((v) => ListTile(
        title: Text('Venta #${v['id']} · ${v['cliente_nombre']}'), subtitle: Text('${v['estado']}\n${fechaLocal(v['fecha_creacion'])}'),
        isThreeLine: true, trailing: Text('\$${v['total']}'), onTap: () => detalle(v),
      )).toList())),]),
    floatingActionButton: FloatingActionButton(onPressed: cargando || anulando ? null : () async {
      final resultado = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => NuevaVentaPage(token: widget.token)));
      if (!mounted) return;
      await cargar();
      if (resultado == true && mounted) aviso(context, 'Venta registrada. Inventario actualizado.');
    }, child: const Icon(Icons.add)),
  ));
}

class NuevaVentaPage extends StatefulWidget {
  final String token;
  const NuevaVentaPage({super.key, required this.token});
  @override
  State<NuevaVentaPage> createState() => _NuevaVentaPageState();
}
class _NuevaVentaPageState extends State<NuevaVentaPage> {
  List<Map<String, dynamic>> clientes = [], productos = [];
  final Map<int, int> cantidades = {};
  final observacion = TextEditingController();
  int? clienteId;
  bool cargando = true, ocupado = false, confirmando = false, incierto = false, finalizado = false;
  String? error;
  int get total => productos.fold<int>(0, (s, p) => s + centavos(p['precio']) * (cantidades[p['id']] ?? 0));
  @override
  void initState() { super.initState(); cargar(); }
  @override
  void dispose() { observacion.dispose(); super.dispose(); }
  Future<void> cargar() async {
    setState(() { cargando = true; error = null; });
    try {
      final d = await Future.wait([
        api('/clientes', token: widget.token), api('/productos', token: widget.token), api('/inventario', token: widget.token),
      ]);
      final cs = lista(d[0]['clientes']);
      final ps = lista(d[1]['productos']);
      final stock = {for (final i in lista(d[2]['inventario'])) i['producto_id']: i['existencia']};
      for (final p in ps) { p['existencia'] = stock[p['id']] ?? 0; }
      if (mounted) setState(() { clientes = cs; productos = ps; });
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => cargando = false); }
  }
  Future<void> elegir(Map<String, dynamic> p) async {
    final id = p['id'] as int;
    final n = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => CantidadPage(
      nombre: p['nombre'].toString(), stock: p['existencia'] as int, inicial: cantidades[id] ?? 1)));
    if (mounted && n != null) setState(() => cantidades[id] = n);
  }
  Future<void> guardar() async {
    if (ocupado || confirmando || incierto || finalizado) return;
    if (clienteId == null || cantidades.isEmpty) { aviso(context, 'Selecciona un cliente y agrega productos'); return; }
    setState(() => confirmando = true);
    final ok = await confirmar(context, 'Confirmar venta',
      'Total estimado: \$${dinero(total)}. El servidor usará los precios actuales y descontará el inventario.');
    if (!mounted) return;
    setState(() => confirmando = false);
    if (!ok) return;
    setState(() => ocupado = true);
    try {
      await api('/ventas', token: widget.token, metodo: 'POST', datos: {
        'cliente_id': clienteId, 'observacion': observacion.text.trim(),
        'productos': cantidades.entries.map((e) => {'producto_id': e.key, 'cantidad': e.value}).toList(),
      });
      if (!mounted) return;
      setState(() { ocupado = false; finalizado = true; });
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) Navigator.pop(context, true); });
    } catch (e) {
      if (!mounted) return;
      if (e is ErrorApi && e.incierto) setState(() => incierto = true);
      aviso(context, incierto ? '$e Comprueba la lista de ventas antes de repetir.' : e.toString());
    } finally { if (mounted) setState(() => ocupado = false); }
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !ocupado, child: Scaffold(
    appBar: AppBar(title: const Text('Nueva venta')),
    body: cargando ? const Center(child: CircularProgressIndicator()) : error != null ? fallo(error!, cargar)
      : AbsorbPointer(absorbing: ocupado || confirmando || incierto || finalizado, child: ListView(padding: const EdgeInsets.all(20), children: [
        if (clientes.isEmpty) const Text('Primero registra un cliente en Clientes.'),
        DropdownButtonFormField<int>(initialValue: clienteId, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Cliente', border: OutlineInputBorder()),
          items: clientes.map((c) => DropdownMenuItem<int>(value: c['id'] as int,
            child: Text(c['nombre'].toString(), overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setState(() => clienteId = v)),
        const SizedBox(height: 20), const Text('Toca un producto para indicar la cantidad.'),
        ...productos.map((p) {
          final id = p['id'] as int;
          final n = cantidades[id] ?? 0;
          return Card(child: ListTile(title: Text(p['nombre'].toString()),
            subtitle: Text('Precio: \$${p['precio']} · Stock: ${p['existencia']}\nCantidad: $n · Subtotal: \$${dinero(centavos(p['precio']) * n)}'),
            isThreeLine: true, onTap: (p['existencia'] as int) > 0 ? () => elegir(p) : null,
            trailing: n > 0 ? IconButton(onPressed: () => setState(() => cantidades.remove(id)), icon: const Icon(Icons.remove_circle_outline))
              : Icon((p['existencia'] as int) > 0 ? Icons.add : Icons.block)));
        }),
        const SizedBox(height: 16),
        TextField(controller: observacion, maxLength: 250, decoration: const InputDecoration(labelText: 'Observación (opcional)', border: OutlineInputBorder())),
        Text('Total estimado: \$${dinero(total)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        FilledButton(onPressed: clienteId == null || cantidades.isEmpty ? null : guardar, child: Text(ocupado ? 'Guardando...' : 'Guardar venta')),
      ])),
    bottomNavigationBar: incierto ? SafeArea(child: Padding(padding: const EdgeInsets.all(16), child:
      FilledButton(onPressed: () => Navigator.pop(context, false), child: const Text('Volver y comprobar ventas')))) : null,
  ));
}

class CantidadPage extends StatefulWidget {
  final String nombre;
  final int stock, inicial;
  const CantidadPage({super.key, required this.nombre, required this.stock, required this.inicial});
  @override
  State<CantidadPage> createState() => _CantidadPageState();
}
class _CantidadPageState extends State<CantidadPage> {
  final form = GlobalKey<FormState>();
  late final TextEditingController cantidad;
  @override
  void initState() { super.initState(); cantidad = TextEditingController(text: '${widget.inicial}'); }
  @override
  void dispose() { cantidad.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.nombre)),
    body: Form(key: form, child: ListView(padding: const EdgeInsets.all(24), children: [
      Text('Disponible: ${widget.stock}'), const SizedBox(height: 16),
      TextFormField(controller: cantidad, autofocus: true, keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Cantidad', border: OutlineInputBorder()),
        validator: (v) { final n = int.tryParse(v ?? ''); return n == null || n < 1 || n > widget.stock ? 'Ingresa entre 1 y ${widget.stock}' : null; }),
      const SizedBox(height: 20),
      FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(context, int.parse(cantidad.text)); }, child: const Text('Agregar')),
    ])),
  );
}

String fechaLocal(dynamic valor) {
  final f=DateTime.tryParse(valor.toString());
  if(f==null)return valor.toString();
  final e=f.toUtc().subtract(const Duration(hours:5));
  return '${e.day.toString().padLeft(2,'0')}/${e.month.toString().padLeft(2,'0')}/${e.year} ${e.hour.toString().padLeft(2,'0')}:${e.minute.toString().padLeft(2,'0')}';
}

class ResumenPage extends StatefulWidget {
  final String token;
  const ResumenPage({super.key,required this.token});
  @override
  State<ResumenPage> createState()=>_ResumenPageState();
}
class _ResumenPageState extends State<ResumenPage> {
  Map<String,dynamic>? datos;
  bool cargando=true;
  String? error;
  @override
  void initState(){super.initState();cargar();}
  Future<void> cargar()async{
    setState((){cargando=true;error=null;});
    try{
      final d=await api('/resumen',token:widget.token);
      if(mounted)setState(()=>datos=Map<String,dynamic>.from(d['resumen'] as Map));
    }catch(e){if(mounted)setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>cargando=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Resumen del día'),actions:[IconButton(onPressed:cargando?null:cargar,icon:const Icon(Icons.refresh))]),
    body:cargando?const Center(child:CircularProgressIndicator()):error!=null?fallo(error!,cargar):ListView(padding:const EdgeInsets.all(20),children:[
      const Text('Ventas registradas de hoy · hora de Ecuador. Las ventas anuladas se excluyen.'),
      const SizedBox(height:16),
      ...<String,String>{'Ventas de hoy':'${datos!['ventas_hoy']}','Total vendido hoy':'\$${datos!['total_hoy']}',
        'Clientes activos':'${datos!['clientes']}','Productos activos':'${datos!['productos']}',
        'Productos sin existencias':'${datos!['sin_stock']}','Stock bajo (1 a 5 unidades)':'${datos!['stock_bajo']}'}.entries
        .map((e)=>Card(child:ListTile(title:Text(e.key),trailing:Text(e.value,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold))))),
      const SizedBox(height:16),
      FilledButton(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>InventarioPage(token:widget.token))),child:const Text('Revisar inventario')),
    ]),
  );
}

class FiltrosFechas extends StatelessWidget {
  final TextEditingController busqueda;
  final DateTime? desde,hasta;
  final VoidCallback aplicar,limpiar;
  final ValueChanged<DateTime?> cambiarDesde,cambiarHasta;
  final bool ocupado;
  final String etiqueta;
  const FiltrosFechas({super.key,required this.busqueda,required this.desde,required this.hasta,required this.aplicar,
    required this.limpiar,required this.cambiarDesde,required this.cambiarHasta,required this.ocupado,required this.etiqueta});
  Future<void> elegir(BuildContext context,bool inicial)async{
    final f=await showDatePicker(context:context,initialDate:(inicial?desde:hasta)??DateTime.now(),firstDate:DateTime(2000),lastDate:DateTime(2100));
    if(f!=null){if(inicial)cambiarDesde(f);else cambiarHasta(f);}
  }
  String texto(DateTime? f)=>f==null?'Sin fecha':'${f.year}-${f.month.toString().padLeft(2,'0')}-${f.day.toString().padLeft(2,'0')}';
  @override
  Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.all(12),child:Column(children:[
    TextField(controller:busqueda,enabled:!ocupado,maxLength:150,onSubmitted:(_)=>aplicar(),decoration:InputDecoration(labelText:etiqueta,prefixIcon:const Icon(Icons.search),border:const OutlineInputBorder())),
    Wrap(spacing:8,runSpacing:8,children:[
      OutlinedButton(onPressed:ocupado?null:()=>elegir(context,true),child:Text('Desde: ${texto(desde)}')),
      OutlinedButton(onPressed:ocupado?null:()=>elegir(context,false),child:Text('Hasta: ${texto(hasta)}')),
      FilledButton(onPressed:ocupado?null:aplicar,child:const Text('Buscar')),
      TextButton(onPressed:ocupado?null:limpiar,child:const Text('Limpiar')),
    ]),
  ]));
}

String consultaFiltros(String ruta,String busqueda,DateTime? desde,DateTime? hasta){
  String f(DateTime d)=>'${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  return Uri(path:ruta,queryParameters:{'busqueda':busqueda.trim(),if(desde!=null)'desde':f(desde),if(hasta!=null)'hasta':f(hasta)}).toString();
}

class HistorialPage extends StatefulWidget {
  final String token;
  const HistorialPage({super.key,required this.token});
  @override
  State<HistorialPage> createState()=>_HistorialPageState();
}
class _HistorialPageState extends State<HistorialPage> {
  final busqueda=TextEditingController();
  DateTime? desde,hasta;
  List<Map<String,dynamic>> registros=[];
  bool cargando=true;
  String? error;
  @override
  void initState(){super.initState();cargar();}
  @override
  void dispose(){busqueda.dispose();super.dispose();}
  Future<void> cargar()async{
    if(desde!=null&&hasta!=null&&desde!.isAfter(hasta!)){aviso(context,'Revisa el intervalo de fechas');return;}
    setState((){cargando=true;error=null;});
    try{
      final d=await api(consultaFiltros('/inventario/historial',busqueda.text,desde,hasta),token:widget.token);
      if(mounted)setState(()=>registros=lista(d['movimientos']));
    }catch(e){if(mounted)setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>cargando=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Historial de inventario')),
    body:Column(children:[
      FiltrosFechas(busqueda:busqueda,desde:desde,hasta:hasta,aplicar:cargar,ocupado:cargando,etiqueta:'Nombre del producto',
        cambiarDesde:(f)=>setState(()=>desde=f),cambiarHasta:(f)=>setState(()=>hasta=f),limpiar:(){busqueda.clear();setState((){desde=null;hasta=null;});cargar();}),
      const Text('Hasta 200 movimientos · fechas de Ecuador'),
      Expanded(child:cargando?const Center(child:CircularProgressIndicator()):error!=null?fallo(error!,cargar)
        :registros.isEmpty?const Center(child:Text('No hay movimientos con estos filtros.'))
        :ListView(children:registros.map((m)=>Card(child:ListTile(
          leading:Icon(m['tipo']=='entrada'?Icons.arrow_downward:Icons.arrow_upward,color:m['tipo']=='entrada'?Colors.green:Colors.orange),
          title:Text('${m['nombre']} · ${m['tipo']} ${m['cantidad']}'),
          subtitle:Text('${m['motivo']}\nExistencias: ${m['existencia_anterior']} → ${m['existencia_nueva']}\n${fechaLocal(m['fecha'])} · ${m['usuario_nombre']}'),
        ))).toList())),
    ]),
  );
}