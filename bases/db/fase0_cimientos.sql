-- =====================================================================
-- FASE 0 · CIMIENTOS
-- ---------------------------------------------------------------------
-- Lo mínimo para que exista la app: las cuatro capas, quién entra
-- (usuarios, roles, conductores), con qué se trabaja (empresas, camiones,
-- remolques), dónde se guardan los archivos y cómo queda registrado todo
-- (parámetros, interruptores de funciones, auditoría, tareas e ingesta).
--
-- Reglas de toda la base de datos:
--   · Nombres en español, en minúsculas y con guiones bajos. Tablas en plural.
--   · Cada número lleva la unidad en el nombre: litros, precio_eur_l,
--     importe_eur, distancia_km, desvio_min. Nunca un número suelto.
--   · Fecha y hora en timestamptz (se guarda en UTC y se muestra en hora de
--     Madrid). Días sin hora en date: fecha, mes (día 1), semana (lunes).
--   · Dinero y litros en numeric, nunca en float.
--   · Listas cerradas con CHECK; listas que pueden crecer, en su propia tabla.
--   · Nada se borra: los maestros se desactivan (activo = false) y los hechos
--     se anulan (anulado_en). La auditoría guarda quién cambió qué.
--   · Todo dato que llega de fuera lleva lote_id: siempre se puede volver al
--     archivo, correo o respuesta de la API de la que salió.
--   · Las tablas y las columnas que no se explican solas llevan comentario
--     (COMMENT ON): la base de datos se lee sola en DBeaver, pgAdmin o psql.
--   · Migraciones solo hacia delante: un archivo aplicado no se edita; si algo
--     sale mal, se corrige con otro archivo.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE SCHEMA ingesta;
CREATE SCHEMA nucleo;
CREATE SCHEMA calculo;
CREATE SCHEMA sistema;

COMMENT ON SCHEMA ingesta IS 'Lo que llega de fuera, tal cual llega: archivos, correos y respuestas de API. Nunca se edita; si algo está mal, se reimporta.';
COMMENT ON SCHEMA nucleo  IS 'La verdad del negocio: datos limpios, con claves y reglas. Es lo que lee y escribe la app.';
COMMENT ON SCHEMA calculo IS 'Lo que se deduce de nucleo: vistas y resultados guardados. Nadie lo edita a mano; se puede borrar y recalcular.';
COMMENT ON SCHEMA sistema IS 'Cómo funciona la app: parámetros, interruptores de funciones, auditoría, tareas y notificaciones.';


-- Utilidades -----------------------------------------------------------

CREATE FUNCTION sistema.tocar_actualizado_en() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.actualizado_en := now();
  RETURN NEW;
END $$;
COMMENT ON FUNCTION sistema.tocar_actualizado_en() IS 'Pone actualizado_en a la hora actual en cada UPDATE. Se engancha con un trigger en cada tabla que tiene esa columna.';

CREATE FUNCTION nucleo.normalizar_matricula(p_matricula text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT upper(regexp_replace(p_matricula, '[^A-Za-z0-9]', '', 'g'))
$$;
COMMENT ON FUNCTION nucleo.normalizar_matricula(text) IS 'Matrícula sin espacios ni guiones y en mayúsculas: «5963 hfh» → «5963HFH». Así cruzan Movildata, Solred y la app.';

CREATE FUNCTION calculo.distancia_km(lat1 numeric, lon1 numeric, lat2 numeric, lon2 numeric) RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$
  SELECT round((6371 * 2 * asin(sqrt(
      power(sin(radians(lat2 - lat1) / 2), 2)
    + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lon2 - lon1) / 2), 2)
  )))::numeric, 2)
$$;
COMMENT ON FUNCTION calculo.distancia_km(numeric, numeric, numeric, numeric) IS 'Distancia en línea recta (km) entre dos puntos. Sirve para descartar rápido; la distancia por carretera la da el servicio de rutas.';


-- Personas y acceso ----------------------------------------------------

CREATE TABLE nucleo.empresas (
  codigo           text PRIMARY KEY,
  nombre           text NOT NULL,
  odoo_empresa_id  integer UNIQUE,
  activa           boolean NOT NULL DEFAULT true
);
COMMENT ON TABLE nucleo.empresas IS 'Empresas del grupo. Cada camión, remolque y conductor pertenece a una.';
COMMENT ON COLUMN nucleo.empresas.odoo_empresa_id IS 'Id de la compañía en Odoo (DECA la necesita para buscar pedidos).';

INSERT INTO nucleo.empresas (codigo, nombre, odoo_empresa_id) VALUES
  ('stinsa',    'STINSA',           1),
  ('transargi', 'TRANSARGI S.L.U.', 7);

CREATE TABLE nucleo.roles (
  codigo       text PRIMARY KEY,
  nombre       text NOT NULL,
  descripcion  text NOT NULL,
  permisos     text[] NOT NULL DEFAULT '{}'
);
COMMENT ON TABLE nucleo.roles IS 'Perfiles de acceso. Añadir tráfico, oficina, taller o dirección es un INSERT, no un cambio de estructura.';
COMMENT ON COLUMN nucleo.roles.permisos IS 'Permisos que comprueba la API, p. ej. {flota.ver, conductores.editar}. «*» = todos; «propio» = solo sus datos.';

INSERT INTO nucleo.roles (codigo, nombre, descripcion, permisos) VALUES
  ('admin',     'Administración', 'Ve y gestiona todo. Provisional hasta definir los perfiles de tráfico, oficina, taller y dirección.', '{*}'),
  ('conductor', 'Conductor',      'Solo ve y escribe sus propios datos.', '{propio}');

CREATE TABLE nucleo.usuarios (
  id                 bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  nombre             text NOT NULL,
  rol                text NOT NULL REFERENCES nucleo.roles,
  codigo             text UNIQUE,
  email              text,
  pin_hash           text,
  clave_hash         text,
  intentos_fallidos  smallint NOT NULL DEFAULT 0,
  bloqueado_hasta    timestamptz,
  en_piloto          boolean NOT NULL DEFAULT false,
  activo             boolean NOT NULL DEFAULT true,
  ultimo_acceso_en   timestamptz,
  creado_en          timestamptz NOT NULL DEFAULT now(),
  actualizado_en     timestamptz NOT NULL DEFAULT now(),
  CHECK (codigo IS NOT NULL OR email IS NOT NULL)
);
CREATE UNIQUE INDEX usuarios_email_unico ON nucleo.usuarios (lower(email));
CREATE TRIGGER usuarios_actualizado BEFORE UPDATE ON nucleo.usuarios FOR EACH ROW EXECUTE FUNCTION sistema.tocar_actualizado_en();
COMMENT ON TABLE nucleo.usuarios IS 'Todo el que entra en la app: conductores (código + PIN) y oficina (email + contraseña).';
COMMENT ON COLUMN nucleo.usuarios.codigo IS 'Código de conductor con el que entra en el móvil.';
COMMENT ON COLUMN nucleo.usuarios.pin_hash IS 'PIN de 4 cifras cifrado con argon2. El PIN nunca se guarda.';
COMMENT ON COLUMN nucleo.usuarios.clave_hash IS 'Contraseña de oficina cifrada con argon2.';
COMMENT ON COLUMN nucleo.usuarios.bloqueado_hasta IS 'Tras sistema.parametro(acceso.intentos_max) fallos seguidos. Solo administración resetea el PIN.';
COMMENT ON COLUMN nucleo.usuarios.en_piloto IS 'Ve las funciones encendidas en modo «piloto» (sistema.funciones).';

CREATE TABLE nucleo.dispositivos (
  id             bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  usuario_id     bigint NOT NULL REFERENCES nucleo.usuarios,
  token_hash     text NOT NULL UNIQUE,
  nombre         text,
  creado_en      timestamptz NOT NULL DEFAULT now(),
  ultimo_uso_en  timestamptz,
  revocado_en    timestamptz
);
CREATE INDEX dispositivos_usuario ON nucleo.dispositivos (usuario_id);
COMMENT ON TABLE nucleo.dispositivos IS 'Móviles recordados: al día siguiente el conductor solo pone el PIN. Revocar uno lo obliga a entrar con código otra vez.';
COMMENT ON COLUMN nucleo.dispositivos.token_hash IS 'Huella del token que guarda el móvil. El token en claro nunca se guarda.';

CREATE TABLE nucleo.archivos (
  id               bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  ruta             text NOT NULL UNIQUE,
  nombre_original  text,
  tipo_mime        text NOT NULL,
  bytes            bigint NOT NULL CHECK (bytes >= 0),
  sha256           text NOT NULL,
  subido_por       bigint REFERENCES nucleo.usuarios,
  subido_en        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX archivos_sha256 ON nucleo.archivos (sha256);
COMMENT ON TABLE nucleo.archivos IS 'Todos los archivos (fotos de tickets, documentos, Excel, PDF, firmas). El archivo vive en disco; aquí, dónde está y su huella.';
COMMENT ON COLUMN nucleo.archivos.ruta IS 'Ruta dentro del volumen de archivos, p. ej. tickets/2026/10/8f3a….jpg.';
COMMENT ON COLUMN nucleo.archivos.sha256 IS 'Huella del contenido: detecta el mismo archivo subido dos veces.';


-- Cómo funciona la app ---------------------------------------------------

CREATE TABLE sistema.parametros (
  id             bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  clave          text NOT NULL,
  valor          jsonb NOT NULL,
  unidad         text,
  vigente_desde  date NOT NULL DEFAULT current_date,
  descripcion    text NOT NULL,
  cambiado_por   bigint REFERENCES nucleo.usuarios,
  creado_en      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (clave, vigente_desde)
);
COMMENT ON TABLE sistema.parametros IS 'Números que decide la empresa y pueden cambiar (desvío máximo, ayuda al gasóleo, tramos de monedas…). Nunca se pisan: un cambio es una fila nueva con su fecha, y los cálculos de un mes usan el valor de ese mes.';
COMMENT ON COLUMN sistema.parametros.vigente_desde IS 'Desde qué día vale. El valor de una fecha es el de la fila más reciente que no la supera.';

CREATE FUNCTION sistema.parametro(p_clave text, p_fecha date DEFAULT current_date) RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT valor
  FROM sistema.parametros
  WHERE clave = p_clave AND vigente_desde <= p_fecha
  ORDER BY vigente_desde DESC
  LIMIT 1
$$;
COMMENT ON FUNCTION sistema.parametro(text, date) IS 'Valor de un parámetro en una fecha: sistema.parametro(''repostaje.desvio_max_min'').';

INSERT INTO sistema.parametros (clave, valor, unidad, vigente_desde, descripcion) VALUES
  ('zona_horaria',         '"Europe/Madrid"', NULL,        '2026-10-01', 'Zona horaria para decidir a qué día pertenece cada dato.'),
  ('acceso.intentos_max',  '5',               'intentos',  '2026-10-01', 'PIN fallidos seguidos antes de bloquear el acceso.'),
  ('acceso.bloqueo_min',   '15',              'min',       '2026-10-01', 'Minutos de bloqueo tras agotar los intentos. Valor inicial, a revisar.');

CREATE TABLE sistema.funciones (
  codigo          text PRIMARY KEY,
  nombre          text NOT NULL,
  fase            smallint NOT NULL CHECK (fase BETWEEN 0 AND 8),
  estado          text NOT NULL DEFAULT 'apagada' CHECK (estado IN ('apagada', 'piloto', 'todos')),
  descripcion     text,
  actualizado_en  timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER funciones_actualizado BEFORE UPDATE ON sistema.funciones FOR EACH ROW EXECUTE FUNCTION sistema.tocar_actualizado_en();
COMMENT ON TABLE sistema.funciones IS 'Interruptores: cada función nace «apagada», pasa a «piloto» (solo usuarios en_piloto) y después a «todos». Permite subir código a medias sin que nadie lo vea.';

CREATE TABLE sistema.auditoria (
  id                  bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  ocurrido_en         timestamptz NOT NULL DEFAULT now(),
  usuario_id          bigint REFERENCES nucleo.usuarios,
  accion              text NOT NULL CHECK (accion IN ('acceder', 'ver', 'crear', 'modificar', 'anular', 'importar', 'exportar')),
  entidad             text NOT NULL,
  entidad_id          text,
  sobre_conductor_id  bigint,
  antes               jsonb,
  despues             jsonb,
  motivo              text,
  ip                  inet
);
CREATE INDEX auditoria_entidad ON sistema.auditoria (entidad, entidad_id);
CREATE INDEX auditoria_conductor ON sistema.auditoria (sobre_conductor_id, ocurrido_en);
COMMENT ON TABLE sistema.auditoria IS 'Quién hizo o vio qué, y cuándo. Responde a «¿quién ha mirado mis datos?» (LOPDGDD) y a «¿quién cambió esta asignación?».';
COMMENT ON COLUMN sistema.auditoria.usuario_id IS 'Vacío = lo hizo una tarea automática.';
COMMENT ON COLUMN sistema.auditoria.entidad IS 'Tabla afectada, p. ej. nucleo.asignaciones.';
COMMENT ON COLUMN sistema.auditoria.sobre_conductor_id IS 'De qué conductor son los datos vistos o tocados.';

CREATE TABLE sistema.ejecuciones (
  id       bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  tarea    text NOT NULL,
  inicio   timestamptz NOT NULL DEFAULT now(),
  fin      timestamptz,
  estado   text NOT NULL DEFAULT 'en_curso' CHECK (estado IN ('en_curso', 'ok', 'sin_datos', 'error')),
  filas    integer,
  detalle  text
);
CREATE INDEX ejecuciones_tarea ON sistema.ejecuciones (tarea, inicio DESC);
COMMENT ON TABLE sistema.ejecuciones IS 'Cada vez que corre una tarea programada (sincronizar Movildata, leer el correo, calcular notas…): cuándo, cómo acabó y cuántas filas tocó.';


-- Ingesta: lo que llega de fuera ----------------------------------------

CREATE TABLE ingesta.lotes (
  id              bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  origen          text NOT NULL CHECK (origen IN (
                    'movildata', 'red_informe_mes', 'red_detalle', 'red_estaciones',
                    'correo_precios', 'ministerio_precios', 'odoo', 'ticket_foto', 'agente_adr', 'manual')),
  descripcion     text,
  archivo_id      bigint REFERENCES nucleo.archivos,
  huella          text,
  periodo_desde   date,
  periodo_hasta   date,
  estado          text NOT NULL DEFAULT 'recibido' CHECK (estado IN ('recibido', 'en_revision', 'importado', 'descartado', 'error')),
  filas_total     integer,
  filas_ok        integer,
  filas_error     integer,
  mapeo_columnas  jsonb,
  error           text,
  ejecucion_id    bigint REFERENCES sistema.ejecuciones,
  recibido_en     timestamptz NOT NULL DEFAULT now(),
  importado_en    timestamptz,
  importado_por   bigint REFERENCES nucleo.usuarios,
  UNIQUE (origen, huella)
);
CREATE INDEX lotes_origen ON ingesta.lotes (origen, recibido_en DESC);
COMMENT ON TABLE ingesta.lotes IS 'Cada entrega de datos: un Excel de Solred, un correo de precios, una llamada a Movildata. Todo dato de nucleo que vino de fuera apunta a su lote.';
COMMENT ON COLUMN ingesta.lotes.huella IS 'sha256 del archivo o de la respuesta. Impide importar dos veces lo mismo.';
COMMENT ON COLUMN ingesta.lotes.estado IS 'recibido → en_revision (filas con error a la vista) → importado. O descartado / error.';
COMMENT ON COLUMN ingesta.lotes.mapeo_columnas IS 'Qué columna del archivo va a qué campo. Si Solred cambia el Excel, se cambia aquí, no el código.';

CREATE TABLE ingesta.filas (
  lote_id     bigint NOT NULL REFERENCES ingesta.lotes ON DELETE CASCADE,
  n_fila      integer NOT NULL,
  datos       jsonb NOT NULL,
  estado      text NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente', 'ok', 'aviso', 'error', 'ignorada')),
  mensaje     text,
  destino     text,
  destino_id  bigint,
  PRIMARY KEY (lote_id, n_fila)
);
COMMENT ON TABLE ingesta.filas IS 'Cada fila de un archivo, tal cual se leyó, con su veredicto. Es la «lista de filas a revisar antes de confirmar» del importador.';
COMMENT ON COLUMN ingesta.filas.datos IS 'La fila original: {"Matrícula": "5963 HFH", "Litros": "252,4", …}.';
COMMENT ON COLUMN ingesta.filas.mensaje IS 'Por qué no entró o qué hay que revisar, en lenguaje claro: «La matrícula 1234ABC no existe».';
COMMENT ON COLUMN ingesta.filas.destino IS 'Tabla donde acabó la fila (p. ej. nucleo.repostajes); destino_id es su id.';

CREATE TABLE ingesta.respuestas_api (
  id            bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  lote_id       bigint REFERENCES ingesta.lotes ON DELETE CASCADE,
  servicio      text NOT NULL CHECK (servicio IN ('movildata', 'rutas', 'ministerio', 'odoo', 'vision')),
  endpoint      text NOT NULL,
  parametros    jsonb,
  estado_http   smallint,
  cuerpo        jsonb,
  duracion_ms   integer,
  recibido_en   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX respuestas_api_recibido ON ingesta.respuestas_api (servicio, recibido_en DESC);
COMMENT ON TABLE ingesta.respuestas_api IS 'Respuestas de API en bruto. Si Movildata cambia un nombre de campo, aquí se ve qué llegó. Se purgan a los 30 días salvo las de error.';
COMMENT ON COLUMN ingesta.respuestas_api.parametros IS 'Parámetros de la llamada sin la clave (apiKey nunca se guarda).';


-- Flota y conductores ----------------------------------------------------

CREATE TABLE nucleo.conductores (
  id                 bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  usuario_id         bigint NOT NULL UNIQUE REFERENCES nucleo.usuarios,
  empresa            text REFERENCES nucleo.empresas,
  tarjeta_tacografo  text UNIQUE,
  base               text,
  telefono           text,
  fecha_alta         date,
  fecha_baja         date,
  creado_en          timestamptz NOT NULL DEFAULT now(),
  actualizado_en     timestamptz NOT NULL DEFAULT now(),
  CHECK (fecha_baja IS NULL OR fecha_alta IS NULL OR fecha_baja >= fecha_alta)
);
CREATE TRIGGER conductores_actualizado BEFORE UPDATE ON nucleo.conductores FOR EACH ROW EXECUTE FUNCTION sistema.tocar_actualizado_en();
COMMENT ON TABLE nucleo.conductores IS 'Datos de cada chófer. El nombre, el código y el PIN están en nucleo.usuarios (uno a uno).';
COMMENT ON COLUMN nucleo.conductores.tarjeta_tacografo IS 'Nº de su tarjeta de conductor. Es la llave con Movildata: dice en qué camión está y qué hace.';

CREATE TABLE nucleo.vehiculos (
  id                        bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  matricula                 text NOT NULL UNIQUE,
  empresa                   text REFERENCES nucleo.empresas,
  alias                     text,
  marca_modelo              text,
  id_movildata              text UNIQUE,
  base                      text,
  qr_token                  text NOT NULL UNIQUE DEFAULT replace(gen_random_uuid()::text, '-', ''),
  tacografo_digital         boolean NOT NULL DEFAULT true,
  consumo_objetivo_l_100km  numeric(4,1),
  fecha_matriculacion       date,
  activo                    boolean NOT NULL DEFAULT true,
  lote_id                   bigint REFERENCES ingesta.lotes,
  creado_en                 timestamptz NOT NULL DEFAULT now(),
  actualizado_en            timestamptz NOT NULL DEFAULT now(),
  CHECK (matricula = nucleo.normalizar_matricula(matricula))
);
CREATE TRIGGER vehiculos_actualizado BEFORE UPDATE ON nucleo.vehiculos FOR EACH ROW EXECUTE FUNCTION sistema.tocar_actualizado_en();
COMMENT ON TABLE nucleo.vehiculos IS 'Cabezas tractoras. La lista inicial sale de Movildata (GetVehiculos).';
COMMENT ON COLUMN nucleo.vehiculos.matricula IS 'Sin espacios ni guiones, en mayúsculas (lo exige un CHECK).';
COMMENT ON COLUMN nucleo.vehiculos.id_movildata IS 'Identificador del vehículo en Movildata (imei).';
COMMENT ON COLUMN nucleo.vehiculos.qr_token IS 'Lo que lleva la pegatina QR de la cabina: elegir camión sin teclear.';
COMMENT ON COLUMN nucleo.vehiculos.tacografo_digital IS 'false = no hay tarjeta que leer: la app pide la matrícula a mano o por QR.';
COMMENT ON COLUMN nucleo.vehiculos.consumo_objetivo_l_100km IS 'Objetivo de consumo de este camión para la nota de conducción.';
COMMENT ON COLUMN nucleo.vehiculos.fecha_matriculacion IS 'Decide la frecuencia de la ITV (anual hasta 10 años, después cada 6 meses).';

CREATE TABLE nucleo.remolques (
  id                   bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  matricula            text NOT NULL UNIQUE,
  empresa              text REFERENCES nucleo.empresas,
  tipo                 text,
  qr_token             text NOT NULL UNIQUE DEFAULT replace(gen_random_uuid()::text, '-', ''),
  fecha_matriculacion  date,
  activo               boolean NOT NULL DEFAULT true,
  creado_en            timestamptz NOT NULL DEFAULT now(),
  actualizado_en       timestamptz NOT NULL DEFAULT now(),
  CHECK (matricula = nucleo.normalizar_matricula(matricula))
);
CREATE TRIGGER remolques_actualizado BEFORE UPDATE ON nucleo.remolques FOR EACH ROW EXECUTE FUNCTION sistema.tocar_actualizado_en();
COMMENT ON TABLE nucleo.remolques IS 'Remolques y semirremolques. El chófer los elige de una lista o escanea su QR.';
COMMENT ON COLUMN nucleo.remolques.tipo IS 'Lona, frigorífico, cisterna, plataforma…';
