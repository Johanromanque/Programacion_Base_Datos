-- 1) Procedimiento “hijo”: inserta en GASTO_COMUN_PAGO_CERO
-- Este procedimiento hace una sola cosa: insertar una fila en la tabla GASTO_COMUN_PAGO_CERO.

CREATE OR REPLACE PROCEDURE sp_ins_gc_pago_cero (
    -- Parametros = datos que se insertarán en la tabla
    p_anno_mes_pcgc             IN NUMBER,    -- Período (YYYYMM) que se está procesando
    p_id_edif                   IN NUMBER,    -- ID del edificio
    p_nombre_edif               IN VARCHAR2,  -- Nombre del edificio
    p_run_administrador         IN VARCHAR2,  -- RUN del administrador (con DV)
    p_nombre_administrador      IN VARCHAR2,  -- Nombre completo del administrador
    p_nro_depto                 IN NUMBER,    -- Número del depto
    p_run_resp_pago_gc          IN VARCHAR2,  -- RUN responsable pago GC
    p_nombre_resp_pago_gc       IN VARCHAR2,  -- Nombre responsable pago GC
    p_valor_multa_pago_cero     IN NUMBER,    -- Multa calculada en pesos
    p_observacion               IN VARCHAR2   -- Mensaje (con corte o sin fecha)
) IS
BEGIN
     -- Inserta una fila en la tabla “resultado” de deudores
    INSERT INTO gasto_comun_pago_cero (
        anno_mes_pcgc, id_edif, nombre_edif,
        run_administrador, nombre_admnistrador,
        nro_depto, run_responsable_pago_gc, nombre_responsable_pago_gc,
        valor_multa_pago_cero, observacion
    )
    VALUES (
        -- Se insertan exactamente los parámetros recibidos
        p_anno_mes_pcgc, p_id_edif, p_nombre_edif,
        p_run_administrador, p_nombre_administrador,
        p_nro_depto, p_run_resp_pago_gc, p_nombre_resp_pago_gc,
        p_valor_multa_pago_cero, p_observacion
    );
END;
/

-- 2) Procedimiento principal: genera deudores y actualiza multas
-- a. Calcula períodos (sin fechas fijas): período a procesar, mes anterior, dos meses atrás.
-- b. Detecta deudores: deptos que no tienen pagos en PAGO_GASTO_COMUN para esos períodos.
-- c. Genera información:
                        -- Inserta en GASTO_COMUN_PAGO_CERO
                        -- Actualiza multa_gc en GASTO_COMUN del período que se está procesando.

CREATE OR REPLACE PROCEDURE sp_gen_deudores_gc (
    p_periodo_proc_yyyymm   IN NUMBER,   -- período que procesas (ej 202405)
    p_valor_uf              IN NUMBER,   -- valor UF en pesos (ej 29509)
    p_uf_mora_1             IN NUMBER DEFAULT 2,  -- multa si debe 1 período
    p_uf_mora_2             IN NUMBER DEFAULT 4   -- multa si debe más de 1 período
) IS
    
    -- A) Fechas/Períodos base
    v_fecha_periodo_proc   DATE;   -- el período convertido a fecha
    v_periodo_prev         NUMBER; -- mes anterior (YYYYMM)
    v_periodo_prev2        NUMBER; -- dos meses atrás (YYYYMM)

    -- B) Variables por fila
    v_multa_uf_count       NUMBER; -- cuántas UF aplicar (2 o 4)
    v_multa_valor          NUMBER; -- UF * valor_uf
    v_obs                  VARCHAR2(80); -- texto observación

BEGIN
    -- Convierte YYYYMM a fecha (1er día del mes)
    v_fecha_periodo_proc := TO_DATE(p_periodo_proc_yyyymm || '01', 'YYYYMMDD');

    -- Períodos anteriores (sin fechas fijas, usando funciones de fecha)
    v_periodo_prev  := TO_NUMBER(TO_CHAR(ADD_MONTHS(v_fecha_periodo_proc, -1), 'YYYYMM'));
    v_periodo_prev2 := TO_NUMBER(TO_CHAR(ADD_MONTHS(v_fecha_periodo_proc, -2), 'YYYYMM'));

    -- Limpieza controlada del período a procesar (para poder re-ejecutar)
    DELETE FROM gasto_comun_pago_cero
    WHERE anno_mes_pcgc = p_periodo_proc_yyyymm;

    -- C) Cursor: deptos con pago cero en periodo_prev
    --     y clasifica si deben 1 o más períodos
    FOR r IN (
        SELECT
            p_periodo_proc_yyyymm              AS anno_mes_proc,
            e.id_edif,
            e.nombre_edif,

            -- RUN administrador (numrun-dv)
            a.numrun_adm || '-' || a.dvrun_adm AS run_admin,
            a.pnombre_adm || ' ' || NVL(a.snombre_adm,'') || ' ' ||
            a.appaterno_adm || ' ' || NVL(a.apmaterno_adm,'') AS nom_admin,

            gc_proc.nro_depto,

            -- Responsable de pago del período que se procesa
            rp.numrun_rpgc || '-' || rp.dvrun_rpgc AS run_resp,
            rp.pnombre_rpgc || ' ' || NVL(rp.snombre_rpgc,'') || ' ' ||
            rp.appaterno_rpgc || ' ' || NVL(rp.apmaterno_rpgc,'') AS nom_resp,

            gc_proc.fecha_pago_gc,

            -- Flags de deuda (pago cero = no existe pago)
            CASE
              WHEN NOT EXISTS (
                   SELECT 1
                   FROM pago_gasto_comun pgc
                   WHERE pgc.anno_mes_pcgc = v_periodo_prev
                     AND pgc.id_edif       = gc_proc.id_edif
                     AND pgc.nro_depto     = gc_proc.nro_depto
              ) THEN 1 ELSE 0
            END AS no_pago_prev,

            CASE
              WHEN NOT EXISTS (
                   SELECT 1
                   FROM pago_gasto_comun pgc
                   WHERE pgc.anno_mes_pcgc = v_periodo_prev2
                     AND pgc.id_edif       = gc_proc.id_edif
                     AND pgc.nro_depto     = gc_proc.nro_depto
              ) THEN 1 ELSE 0
            END AS no_pago_prev2

        FROM gasto_comun gc_proc
        JOIN edificio e
          ON e.id_edif = gc_proc.id_edif
        JOIN administrador a
          ON a.numrun_adm = e.numrun_adm
        JOIN responsable_pago_gasto_comun rp
          ON rp.numrun_rpgc = gc_proc.numrun_rpgc

        WHERE gc_proc.anno_mes_pcgc = p_periodo_proc_yyyymm

        -- Orden solicitado: por nombre edificio y número depto
        ORDER BY e.nombre_edif, gc_proc.nro_depto
    ) LOOP

        -- Solo procesamos los que NO pagaron el período anterior
        IF r.no_pago_prev = 1 THEN

            -- Regla: si no pagó más de un período => multa mayor + corte con fecha
            IF r.no_pago_prev2 = 1 THEN
                v_multa_uf_count := p_uf_mora_2;
                v_multa_valor    := p_valor_uf * v_multa_uf_count;
                v_obs := 'Se realizará el corte del combustible y agua a contar del ' ||
                         TO_CHAR(r.fecha_pago_gc, 'DD/MM/YYYY');
            ELSE
                v_multa_uf_count := p_uf_mora_1;
                v_multa_valor    := p_valor_uf * v_multa_uf_count;
                v_obs := 'Se realizará el corte del combustible y agua';
            END IF;

            -- 1) Insertar en tabla de “pago cero”
            sp_ins_gc_pago_cero(
                p_anno_mes_pcgc         => r.anno_mes_proc,
                p_id_edif               => r.id_edif,
                p_nombre_edif           => r.nombre_edif,
                p_run_administrador     => r.run_admin,
                p_nombre_administrador  => TRIM(r.nom_admin),
                p_nro_depto             => r.nro_depto,
                p_run_resp_pago_gc      => r.run_resp,
                p_nombre_resp_pago_gc   => TRIM(r.nom_resp),
                p_valor_multa_pago_cero => v_multa_valor,
                p_observacion           => v_obs
            );

            -- 2) Actualizar multa del período que se está procesando (GASTO_COMUN)
            UPDATE gasto_comun
               SET multa_gc = v_multa_valor
             WHERE anno_mes_pcgc = p_periodo_proc_yyyymm
               AND id_edif       = r.id_edif
               AND nro_depto     = r.nro_depto;

        END IF;

    END LOOP;

    COMMIT;

END;
/

-- 3) Prueba solicitada: “Mayo del año actual” y UF = 29.509
-- La idea es NO usar una fecha fija. El año sale dinámico.

SET SERVEROUTPUT ON;

VARIABLE b_periodo NUMBER;
VARIABLE b_uf      NUMBER;

-- Mayo del año actual (YYYY05) sin fijar año
EXEC :b_periodo := TO_NUMBER(TO_CHAR(SYSDATE,'YYYY') || '05');
EXEC :b_uf      := 29509;

BEGIN
  sp_gen_deudores_gc(
    p_periodo_proc_yyyymm => :b_periodo,
    p_valor_uf            => :b_uf
    -- si tu profe/pauta usa 2UF y 4UF, deja los defaults
    -- si en tu ejemplo te aparece 1UF/2UF, puedes probar:
    -- , p_uf_mora_1 => 1
    -- , p_uf_mora_2 => 2
  );
END;
/

-- 4) Consultas de verificación (F5)

-- Tabla de deudores generada GASTO_COMUN_PAGO_CERO
SELECT *
FROM gasto_comun_pago_cero
WHERE anno_mes_pcgc = :b_periodo
ORDER BY nombre_edif, nro_depto;

-- Multas aplicadas en GASTO_COMUN para el período procesado
SELECT anno_mes_pcgc, id_edif, nro_depto, fecha_desde_gc, fecha_hasta_gc, multa_gc
FROM gasto_comun
WHERE anno_mes_pcgc = :b_periodo
  AND multa_gc IS NOT NULL
ORDER BY id_edif, nro_depto;