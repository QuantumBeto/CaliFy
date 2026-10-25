/// Datos de conexión con Supabase.
///
/// Dónde encontrarlos: en tu proyecto de Supabase, botón "Connect" (arriba)
/// o Project Settings → API Keys.
///
/// - supabaseUrl:     algo como https://abcdefgh.supabase.co
/// - supabaseAnonKey: la clave "publishable" (empieza con sb_publishable_...)
///                    o la clave "anon" (empieza con eyJ...). Cualquiera sirve.
///
/// Esa clave es PÚBLICA por diseño: la seguridad la ponen las reglas (RLS)
/// de la base de datos, así que es normal que quede en el repositorio.
/// NUNCA pongas aquí la clave "secret" ni la "service_role".
class Config {
  static const String supabaseUrl = 'https://ijtsabgzkcpoalbxovhi.supabase.co';
  // Pega aquí tu clave publishable (empieza con sb_publishable_), entre las comillas,
  // reemplazando PEGA_AQUI_TU_CLAVE_PUBLICA
  static const String supabaseAnonKey = 'sb_publishable_ysu4U-9TVneiHfqbDz0CeA_3y_eBSbn';

  /// La gente entra con "usuario" y contraseña, pero Supabase pide un correo
  /// por dentro: el usuario "juan" se guarda como juan@gmail.com. Es solo un
  /// nombre interno (no se envía ningún correo). Se usa un dominio real porque
  /// Supabase rechaza algunos dominios inventados.
  static const String dominioInterno = 'gmail.com';

  static bool get configurado =>
      supabaseUrl.startsWith('https://') &&
      !supabaseAnonKey.startsWith('PEGA_AQUI');
}
