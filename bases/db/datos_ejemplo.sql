-- =====================================================================
-- DATOS DE EJEMPLO · solo para el entorno local
-- ---------------------------------------------------------------------
-- Todo es inventado (personas, matrículas, tarjetas). Se carga después de
-- las once fases y deja un día de trabajo completo: dos chóferes, dos
-- camiones, un cambio de camión, repostajes, tickets, parte y monedas.
-- También una semana de registro horario, vacaciones (una aprobada y una
-- pedida), fotos del frontal y una tarea a medias con un problema abierto.
-- Las horas son de hoy, en hora de Madrid. A propósito deja dos avisos en
-- calculo.incidencias_tickets (un ticket sin su repostaje de Solred y un
-- repostaje a más de 5 km del camión), para ver el cruce funcionando.
-- =====================================================================

-- Personas
INSERT INTO nucleo.usuarios (nombre, rol, email, clave_hash) VALUES
  ('Tráfico (ejemplo)', 'admin', 'trafico@ejemplo.test', 'argon2-de-ejemplo');

INSERT INTO nucleo.usuarios (nombre, rol, codigo, pin_hash, en_piloto) VALUES
  ('Javier Ejemplo', 'conductor', 'C0001', 'argon2-de-ejemplo', true),
  ('Lucía Ejemplo',  'conductor', 'C0002', 'argon2-de-ejemplo', true);

INSERT INTO nucleo.conductores (usuario_id, empresa, tarjeta_tacografo, base, fecha_alta)
SELECT u.id, 'transargi', t.tarjeta, 'Almassora', DATE '2024-03-01'
FROM nucleo.usuarios u
JOIN (VALUES ('C0001', 'E000000000000001'), ('C0002', 'E000000000000002')) AS t(codigo, tarjeta) ON t.codigo = u.codigo;

-- Flota
INSERT INTO nucleo.vehiculos (matricula, empresa, alias, id_movildata, consumo_objetivo_l_100km, fecha_matriculacion) VALUES
  ('1111BBB', 'transargi', 'Tractora 11', 'IMEI-EJEMPLO-1', 30.0, DATE '2019-05-10'),
  ('2222CCC', 'stinsa',    'Tractora 22', 'IMEI-EJEMPLO-2', 31.5, DATE '2014-02-20');

INSERT INTO nucleo.remolques (matricula, empresa, tipo) VALUES
  ('R1111BBB', 'transargi', 'Lona');

-- Una sincronización de Movildata y su telemetría (cada 30 min)
INSERT INTO ingesta.lotes (origen, descripcion, huella, estado, filas_total, filas_ok, importado_en)
VALUES ('movildata', 'Sincronización de ejemplo', 'ejemplo-movildata-1', 'importado', 24, 24, now());

INSERT INTO nucleo.telemetria (vehiculo_id, ts, lat, lon, velocidad_kmh, km_odometro, motor_encendido, tarjeta_tacografo, lote_id)
SELECT v.id,
       (current_date + time '07:00' + make_interval(mins => 30 * n)) AT TIME ZONE 'Europe/Madrid',
       39.95 - n * 0.02, -0.06 - n * 0.01,
       CASE WHEN n IN (3, 6) THEN 0 ELSE 78 END,
       v.km0 + n * 38,
       true,
       NULL,
       (SELECT id FROM ingesta.lotes WHERE huella = 'ejemplo-movildata-1')
FROM (SELECT id, CASE matricula WHEN '1111BBB' THEN 412000 ELSE 655000 END AS km0 FROM nucleo.vehiculos) v
CROSS JOIN generate_series(0, 11) AS n;

-- Asignaciones: Javier empieza en la 1111BBB y a las 10:00 pasa a la 2222CCC; Lucía coge la 1111BBB a las 10:30
SELECT nucleo.abrir_asignacion(c.id, v.id, (current_date + time '07:00') AT TIME ZONE 'Europe/Madrid', 'tacografo')
FROM nucleo.conductores c, nucleo.vehiculos v
WHERE c.tarjeta_tacografo = 'E000000000000001' AND v.matricula = '1111BBB';

SELECT nucleo.abrir_asignacion(c.id, v.id, (current_date + time '10:00') AT TIME ZONE 'Europe/Madrid', 'tacografo')
FROM nucleo.conductores c, nucleo.vehiculos v
WHERE c.tarjeta_tacografo = 'E000000000000001' AND v.matricula = '2222CCC';

SELECT nucleo.abrir_asignacion(c.id, v.id, (current_date + time '10:30') AT TIME ZONE 'Europe/Madrid', 'qr')
FROM nucleo.conductores c, nucleo.vehiculos v
WHERE c.tarjeta_tacografo = 'E000000000000002' AND v.matricula = '1111BBB';

INSERT INTO nucleo.actividad_tacografo (tarjeta_tacografo, conductor_id, vehiculo_id, actividad, inicio, fin)
SELECT 'E000000000000001', c.id, v.id, a.actividad,
       (current_date + a.desde) AT TIME ZONE 'Europe/Madrid',
       (current_date + a.hasta) AT TIME ZONE 'Europe/Madrid'
FROM nucleo.conductores c, nucleo.vehiculos v,
     (VALUES ('conduccion', time '07:00', time '09:15'),
             ('descanso',   time '09:15', time '10:00'),
             ('conduccion', time '10:00', time '12:30')) AS a(actividad, desde, hasta)
WHERE c.tarjeta_tacografo = 'E000000000000001' AND v.matricula = '1111BBB';

-- Documentos: el carné ADR de Javier caduca en 40 días (ámbar)
INSERT INTO nucleo.documentos (tipo, titular, conductor_id, caduca_el, estado, validado_por, validado_en)
SELECT 'carne_adr', 'conductor', c.id, current_date + 40, 'vigente', (SELECT id FROM nucleo.usuarios WHERE email = 'trafico@ejemplo.test'), now()
FROM nucleo.conductores c WHERE c.tarjeta_tacografo = 'E000000000000001';

INSERT INTO nucleo.documentos (tipo, titular, conductor_id, caduca_el, apto, estado, validado_por, validado_en)
SELECT 'revision_medica', 'conductor', c.id, current_date + 200, true, 'vigente', (SELECT id FROM nucleo.usuarios WHERE email = 'trafico@ejemplo.test'), now()
FROM nucleo.conductores c WHERE c.tarjeta_tacografo = 'E000000000000001';

-- Gasolineras, tarjeta y precios
INSERT INTO nucleo.gasolineras (red, codigo_red, nombre, municipio, provincia, lat, lon, descuento_eur_l, acceso_pesados, id_ministerio) VALUES
  ('solred', 'EJ-001', 'Plana Baixa', 'Vila-real',  'Castellón', 39.938000, -0.101000, 0.220, true, 'MIN-EJ-1'),
  ('solred', 'EJ-002', 'Almassora',   'Almassora',  'Castellón', 39.955000, -0.061000, 0.220, true, 'MIN-EJ-2');

INSERT INTO nucleo.tarjetas_combustible (red, identificador, vehiculo_id)
SELECT 'solred', '**** 0011', id FROM nucleo.vehiculos WHERE matricula = '1111BBB';

INSERT INTO nucleo.precios_ministerio (fecha, id_ministerio, precio_gasoleo_a_eur_l) VALUES
  (current_date, 'MIN-EJ-1', 1.919),
  (current_date, 'MIN-EJ-2', 1.905);

INSERT INTO nucleo.precios_dia (fecha, red, ambito, gasolinera_id, precio_eur_l, origen, cargado_por)
SELECT current_date, 'solred', 'estacion', g.id, 1.630, 'manual', (SELECT id FROM nucleo.usuarios WHERE email = 'trafico@ejemplo.test')
FROM nucleo.gasolineras g WHERE g.codigo_red = 'EJ-002';

-- Excel de Solred: informe del mes pasado y detalle de hoy
INSERT INTO ingesta.lotes (origen, descripcion, huella, estado, importado_en) VALUES
  ('red_informe_mes', 'Informe Vehículos de ejemplo', 'ejemplo-informe-1', 'importado', now()),
  ('red_detalle',     'Detalle de ejemplo',           'ejemplo-detalle-1', 'importado', now());

INSERT INTO nucleo.informes_red_mes (red, mes, vehiculo_id, importe_eur, litros, n_repostajes, pct_optimo, ahorro_perdido_eur, lote_id, n_fila)
SELECT 'solred', date_trunc('month', current_date - interval '1 month')::date, v.id, x.importe, x.litros, x.n, x.pct, x.perdido,
       (SELECT id FROM ingesta.lotes WHERE huella = 'ejemplo-informe-1'), x.fila
FROM nucleo.vehiculos v
JOIN (VALUES ('1111BBB', 3520.40, 2140.00, 8, 41.0, 212.40, 1),
             ('2222CCC', 2980.10, 1810.00, 7, 86.0,  31.10, 2)) AS x(matricula, importe, litros, n, pct, perdido, fila)
  ON x.matricula = v.matricula;

INSERT INTO nucleo.repostajes (red, tarjeta_id, vehiculo_id, fecha_hora, gasolinera_id, litros, precio_eur_l, importe_eur, lote_id, n_fila)
SELECT 'solred', t.id, v.id, (current_date + time '08:30') AT TIME ZONE 'Europe/Madrid', g.id, 312.40, 1.649, 515.15,
       (SELECT id FROM ingesta.lotes WHERE huella = 'ejemplo-detalle-1'), 1
FROM nucleo.vehiculos v
JOIN nucleo.tarjetas_combustible t ON t.vehiculo_id = v.id
JOIN nucleo.gasolineras g ON g.codigo_red = 'EJ-001'
WHERE v.matricula = '1111BBB';

-- Tickets de Javier: un lleno anterior y el de hoy, que cuadra con Solred
INSERT INTO nucleo.archivos (ruta, tipo_mime, bytes, sha256) VALUES
  ('tickets/ejemplo/1.jpg', 'image/jpeg', 120000, 'ejemplo-sha-1'),
  ('tickets/ejemplo/2.jpg', 'image/jpeg', 118000, 'ejemplo-sha-2');

INSERT INTO nucleo.tickets (conductor_id, vehiculo_id, foto_id, fecha_hora, gasolinera_id, litros, precio_eur_l, importe_eur, lleno, km_odometro, estado, repostaje_id)
SELECT c.id, v.id, a.id, x.fecha_hora, g.id, x.litros, x.precio, x.importe, true, x.km, 'confirmado',
       CASE WHEN x.enlazar THEN (SELECT id FROM nucleo.repostajes LIMIT 1) END
FROM nucleo.conductores c
JOIN nucleo.vehiculos v ON v.matricula = '1111BBB'
JOIN nucleo.gasolineras g ON g.codigo_red = 'EJ-001'
JOIN (VALUES ('tickets/ejemplo/1.jpg', (current_date - 3 + time '18:00') AT TIME ZONE 'Europe/Madrid', 280.00, 1.655, 463.40, 410948.0, false),
             ('tickets/ejemplo/2.jpg', (current_date + time '08:30') AT TIME ZONE 'Europe/Madrid',     312.40, 1.649, 515.15, 412000.0, true))
  AS x(ruta, fecha_hora, litros, precio, importe, km, enlazar) ON true
JOIN nucleo.archivos a ON a.ruta = x.ruta
WHERE c.tarjeta_tacografo = 'E000000000000001';

-- Parte del día de Javier en la 1111BBB
INSERT INTO nucleo.partes_dia (vehiculo_id, fecha, conductor_id, lugar, empieza_en, termina_en, km_inicio, km_fin, servicios, remolque_id, estado, confirmado_en)
SELECT v.id, current_date, c.id, 'Almassora',
       (current_date + time '07:00') AT TIME ZONE 'Europe/Madrid',
       (current_date + time '10:00') AT TIME ZONE 'Europe/Madrid',
       412000, 412228, 2, r.id, 'confirmado', now()
FROM nucleo.vehiculos v, nucleo.conductores c, nucleo.remolques r
WHERE v.matricula = '1111BBB' AND c.tarjeta_tacografo = 'E000000000000001' AND r.matricula = 'R1111BBB';

-- Nota de la semana pasada y sus monedas
INSERT INTO calculo.notas_semana (conductor_id, semana, componente, nota)
SELECT c.id, date_trunc('week', current_date - 7)::date, x.componente, x.nota
FROM nucleo.conductores c
JOIN (VALUES ('aceleraciones_frenadas', 8.2), ('ralenti', 6.1), ('velocidad', 8.8),
             ('consumo', 9.0), ('repostaje', 6.4), ('tiempos_pausas', 10)) AS x(componente, nota) ON true
WHERE c.tarjeta_tacografo = 'E000000000000001';

INSERT INTO nucleo.monedas (conductor_id, tipo, cantidad, semana, caduca_el, motivo)
SELECT c.id, 'tramo_semana', 20, date_trunc('week', current_date - 7)::date, current_date + 365, 'Semana pasada: nota 8,1'
FROM nucleo.conductores c WHERE c.tarjeta_tacografo = 'E000000000000001';

-- Un mensaje de Javier a la oficina
INSERT INTO nucleo.conversaciones (tipo, conductor_id, creada_por)
SELECT 'conductor', c.id, c.usuario_id FROM nucleo.conductores c WHERE c.tarjeta_tacografo = 'E000000000000001';

INSERT INTO nucleo.participantes (conversacion_id, usuario_id)
SELECT cv.id, u.id
FROM nucleo.conversaciones cv
JOIN nucleo.conductores c ON c.id = cv.conductor_id
JOIN nucleo.usuarios u ON u.id = c.usuario_id OR u.email = 'trafico@ejemplo.test';

INSERT INTO nucleo.mensajes (conversacion_id, autor_id, texto)
SELECT cv.id, c.usuario_id, 'Llego a la descarga en 20 minutos.'
FROM nucleo.conversaciones cv JOIN nucleo.conductores c ON c.id = cv.conductor_id;


-- Enlace con Odoo y registro horario: Javier lleva seis días de 07:00 a
-- 16:30 y hoy sigue trabajando; a Lucía tráfico le corrigió la entrada de ayer
INSERT INTO nucleo.empleados_odoo (conductor_id, odoo_empleado_id, fecha_antiguedad)
SELECT c.id, x.empleado, DATE '2024-03-01'
FROM nucleo.conductores c
JOIN (VALUES ('E000000000000001', 1501), ('E000000000000002', 1502)) AS x(tarjeta, empleado) ON x.tarjeta = c.tarjeta_tacografo;

INSERT INTO nucleo.jornadas (conductor_id, entrada, salida, origen_entrada, origen_salida, odoo_asistencia_id, copiada_odoo_en)
SELECT c.id,
       (current_date - d + time '07:00') AT TIME ZONE 'Europe/Madrid',
       (current_date - d + time '16:30') AT TIME ZONE 'Europe/Madrid',
       'app', 'app', 9000 + d, now()
FROM nucleo.conductores c
CROSS JOIN generate_series(1, 6) AS d
WHERE c.tarjeta_tacografo = 'E000000000000001';

INSERT INTO nucleo.jornadas (conductor_id, entrada, origen_entrada)
SELECT c.id, (current_date + time '07:00') AT TIME ZONE 'Europe/Madrid', 'app'
FROM nucleo.conductores c WHERE c.tarjeta_tacografo = 'E000000000000001';

INSERT INTO nucleo.jornadas (conductor_id, entrada, salida, origen_entrada, origen_salida, corregida_por, motivo_correccion)
SELECT c.id,
       (current_date - 1 + time '08:00') AT TIME ZONE 'Europe/Madrid',
       (current_date - 1 + time '15:00') AT TIME ZONE 'Europe/Madrid',
       'admin', 'app', (SELECT id FROM nucleo.usuarios WHERE email = 'trafico@ejemplo.test'), 'Olvidó empezar la jornada en la app'
FROM nucleo.conductores c WHERE c.tarjeta_tacografo = 'E000000000000002';

INSERT INTO nucleo.jornadas (conductor_id, entrada, origen_entrada)
SELECT c.id, (current_date + time '10:30') AT TIME ZONE 'Europe/Madrid', 'app'
FROM nucleo.conductores c WHERE c.tarjeta_tacografo = 'E000000000000002';

-- Asistencias de Odoo (las que se pagan): copia de las jornadas, salvo la de
-- ayer de Javier, que RRHH cambió en Odoo (salida a las 18:30, no a las 16:30)
INSERT INTO nucleo.asistencias_odoo (odoo_asistencia_id, conductor_id, entrada, salida, jornada_id, cambiada_en_odoo)
SELECT coalesce(j.odoo_asistencia_id, 9100 + row_number() OVER (ORDER BY j.id))::int,
       j.conductor_id,
       j.entrada,
       CASE WHEN j.odoo_asistencia_id = 9001 THEN j.salida + interval '2 hours' ELSE j.salida END,
       j.id,
       CASE WHEN j.odoo_asistencia_id = 9001 THEN now() - interval '3 hours' END
FROM nucleo.jornadas j;

-- Lo que vio la tarjeta de Javier anteayer (cuadra con Odoo: 5 min) y ayer
-- (9,5 h reales frente a las 11,5 h que ahora tiene Odoo)
INSERT INTO nucleo.actividad_tacografo (tarjeta_tacografo, conductor_id, vehiculo_id, actividad, inicio, fin)
SELECT 'E000000000000001', c.id, v.id, a.actividad,
       (current_date - a.dia + a.desde) AT TIME ZONE 'Europe/Madrid',
       (current_date - a.dia + a.hasta) AT TIME ZONE 'Europe/Madrid'
FROM nucleo.conductores c, nucleo.vehiculos v,
     (VALUES (2, 'conduccion',     time '07:00', time '11:00'),
             (2, 'disponibilidad', time '11:00', time '11:45'),
             (2, 'otro_trabajo',   time '11:45', time '12:30'),
             (2, 'conduccion',     time '12:30', time '16:25'),
             (1, 'conduccion',     time '07:00', time '11:30'),
             (1, 'otro_trabajo',   time '11:30', time '12:00'),
             (1, 'conduccion',     time '12:00', time '16:30')) AS a(dia, actividad, desde, hasta)
WHERE c.tarjeta_tacografo = 'E000000000000001' AND v.matricula = '1111BBB';

-- Vacaciones: saldos copiados de Odoo, unas aprobadas de Javier en verano,
-- otras que acaba de pedir y las de Lucía, ya aprobadas, que se cruzan
INSERT INTO nucleo.saldos_vacaciones (conductor_id, anio, generados_dias, disfrutados_dias, al_final_del_anio_dias)
SELECT c.id, extract(year FROM current_date)::smallint, 25, x.disfrutados, 30
FROM nucleo.conductores c
JOIN (VALUES ('E000000000000001', 9), ('E000000000000002', 20)) AS x(tarjeta, disfrutados) ON x.tarjeta = c.tarjeta_tacografo;

INSERT INTO nucleo.ausencias (conductor_id, tipo, desde, hasta, dias, estado, origen, pedida_en, resuelta_en, odoo_ausencia_id)
SELECT c.id, 'vacaciones', current_date - 90, current_date - 82, 9, 'aprobada', 'odoo', now() - interval '120 days', now() - interval '118 days', 7001
FROM nucleo.conductores c WHERE c.tarjeta_tacografo = 'E000000000000001';

INSERT INTO nucleo.ausencias (conductor_id, tipo, desde, hasta, dias, estado, origen)
SELECT c.id, 'vacaciones', current_date + 20, current_date + 24, 5, 'pedida', 'app'
FROM nucleo.conductores c WHERE c.tarjeta_tacografo = 'E000000000000001';

INSERT INTO nucleo.ausencias (conductor_id, tipo, desde, hasta, dias, estado, origen, pedida_en, resuelta_por, resuelta_en)
SELECT c.id, 'vacaciones', current_date + 22, current_date + 26, 5, 'aprobada', 'app', now() - interval '5 days',
       (SELECT id FROM nucleo.usuarios WHERE email = 'trafico@ejemplo.test'), now() - interval '4 days'
FROM nucleo.conductores c WHERE c.tarjeta_tacografo = 'E000000000000002';

-- Fotos del frontal al coger cada camión
INSERT INTO nucleo.archivos (ruta, tipo_mime, bytes, sha256) VALUES
  ('frontal/ejemplo/1.jpg', 'image/jpeg', 240000, 'ejemplo-sha-frontal-1'),
  ('frontal/ejemplo/2.jpg', 'image/jpeg', 236000, 'ejemplo-sha-frontal-2');

INSERT INTO nucleo.fotos_frontal (conductor_id, vehiculo_id, asignacion_id, archivo_id, tomada_en, matricula_leida, coincide)
SELECT a.conductor_id, a.vehiculo_id, a.id, ar.id, a.inicio + interval '1 minute', v.matricula, true
FROM nucleo.asignaciones a
JOIN nucleo.vehiculos v ON v.id = a.vehiculo_id
JOIN nucleo.conductores c ON c.id = a.conductor_id
JOIN nucleo.archivos ar ON ar.ruta = CASE c.tarjeta_tacografo WHEN 'E000000000000001' THEN 'frontal/ejemplo/1.jpg' ELSE 'frontal/ejemplo/2.jpg' END
WHERE a.fin IS NULL;

-- Tareas: Javier va por «Cargado» y avisa de un retraso; corrigió la orden
-- con DECA desde la tarea. Lucía tiene una pendiente que creó tráfico
INSERT INTO nucleo.tareas (odoo_tarea_id, tipo, conductor_id, vehiculo_id, empresa, titulo, pedido, lugar_carga, lugar_descarga, cita_carga, cita_descarga, notas, estado, origen)
SELECT 5501, 'carga_descarga', c.id, v.id, 'transargi', 'Vila-real → Puerto de Valencia', 'S2630118',
       'Azulejos de ejemplo (Vila-real)', 'Puerto de Valencia, terminal de ejemplo',
       (current_date + time '10:30') AT TIME ZONE 'Europe/Madrid', (current_date + time '14:00') AT TIME ZONE 'Europe/Madrid',
       'Muelle 4. Preguntar por el jefe de almacén.', 'en_curso', 'odoo'
FROM nucleo.conductores c, nucleo.vehiculos v
WHERE c.tarjeta_tacografo = 'E000000000000001' AND v.matricula = '2222CCC';

INSERT INTO nucleo.tareas (tipo, conductor_id, vehiculo_id, titulo, lugar_carga, lugar_descarga, cita_carga, estado, origen, creada_por)
SELECT 'carga_descarga', c.id, v.id, 'Almassora → Castellón', 'Almassora', 'Castellón',
       (current_date + time '15:00') AT TIME ZONE 'Europe/Madrid', 'pendiente', 'panel',
       (SELECT id FROM nucleo.usuarios WHERE email = 'trafico@ejemplo.test')
FROM nucleo.conductores c, nucleo.vehiculos v
WHERE c.tarjeta_tacografo = 'E000000000000002' AND v.matricula = '1111BBB';

INSERT INTO nucleo.tareas_etapas (tarea_id, n, nombre, hecha_en, origen)
SELECT t.id, e.n, e.nombre,
       CASE WHEN t.odoo_tarea_id = 5501 AND e.n <= 3
            THEN (current_date + (ARRAY[time '10:05', time '10:40', time '11:20'])[e.n]) AT TIME ZONE 'Europe/Madrid' END,
       CASE WHEN t.odoo_tarea_id = 5501 AND e.n <= 3 THEN 'app' END
FROM nucleo.tareas t
JOIN nucleo.tipos_tarea tt ON tt.codigo = t.tipo
CROSS JOIN LATERAL unnest(tt.etapas) WITH ORDINALITY AS e(nombre, n);

INSERT INTO nucleo.tareas_problemas (tarea_id, conductor_id, tipo, texto, ocurrido_en)
SELECT t.id, t.conductor_id, 'retraso', 'Cola de unos 40 minutos para entrar a la terminal.', (current_date + time '12:10') AT TIME ZONE 'Europe/Madrid'
FROM nucleo.tareas t WHERE t.odoo_tarea_id = 5501;

INSERT INTO sistema.notificaciones (usuario_id, canal, titulo, cuerpo, origen, origen_id, clave_unica)
SELECT u.id, 'app', 'Retraso en S2630118', p.texto, 'tarea', p.id, 'problema:' || p.id || '|u' || u.id || '|app'
FROM nucleo.tareas_problemas p, nucleo.usuarios u
WHERE u.email = 'trafico@ejemplo.test';

INSERT INTO nucleo.deca_correcciones (conductor_id, empresa, pedido, tarea_odoo_id, antes, despues, resultado)
SELECT c.id, 'transargi', 'S2630118', 5501,
       '{"mercancia": "AZULEJO", "bultos": 22, "euro_palets": 22, "peso_kg": 24800}',
       '{"mercancia": "AZULEJO", "bultos": 24, "euro_palets": 24, "peso_kg": 25300}',
       'guardada'
FROM nucleo.conductores c WHERE c.tarjeta_tacografo = 'E000000000000001';
