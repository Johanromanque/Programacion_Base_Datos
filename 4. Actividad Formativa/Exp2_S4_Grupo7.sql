------------------------------------------------------------
-- CASO 1 — Puntos (Año anterior)
-- Objetivo: procesar TODAS las transacciones del año anterior y:
-- 1) Guardar detalle por transacción en DETALLE_PUNTOS_TARJETA_CATB
-- 2) Guardar resumen mensual en RESUMEN_PUNTOS_TARJETA_CATB
-- Cumpliendo: 2 cursores simultáneos, TRUNCATE en ejecución,
-- VARRAY de puntos, registro PL/SQL y cálculo en PL/SQL.
------------------------------------------------------------

-- ---------------------------------------------------------
-- 1) VARIABLES BIND (paramétricas)
-- ---------------------------------------------------------

-- Año base de ejecución (no fijo): se obtiene dinámicamente desde SYSDATE.
VARIABLE b_anno_ejecucion NUMBER;
EXEC :b_anno_ejecucion := EXTRACT(YEAR FROM SYSDATE);

-- Tramos de monto anual (paramétricos, para puntos extra)
VARIABLE b_tramo1_inf NUMBER;
VARIABLE b_tramo1_sup NUMBER;
VARIABLE b_tramo2_inf NUMBER;
VARIABLE b_tramo2_sup NUMBER;
VARIABLE b_tramo3_inf NUMBER;

-- Asignación valores a los tramos (se pueden cambiar sin editar el bloque PL/SQL)
EXEC :b_tramo1_inf := 500000;
EXEC :b_tramo1_sup := 700000;
EXEC :b_tramo2_inf := 700001;
EXEC :b_tramo2_sup := 900000;
EXEC :b_tramo3_inf := 900001;

-- Puntos normales y extra (también paramétricos)
VARIABLE b_ptos_normal NUMBER;
VARIABLE b_ptos_ext1   NUMBER;
VARIABLE b_ptos_ext2   NUMBER;
VARIABLE b_ptos_ext3   NUMBER;

-- Asignación valores a puntos
EXEC :b_ptos_normal := 250;
EXEC :b_ptos_ext1   := 300;
EXEC :b_ptos_ext2   := 550;
EXEC :b_ptos_ext3   := 700;

-- ---------------------------------------------------------
-- 2) BLOQUE PL/SQL (proceso)
-- ---------------------------------------------------------
SET SERVEROUTPUT ON;

DECLARE
  /* ============================================================
     CASO 1 - PUNTOS ALL THE BEST (AÑO ANTERIOR)

     Requisitos cubiertos:
     - Año anterior dinámico: v_anno_informe := :b_anno_ejecucion - 1
     - TRUNCATE en ejecución: EXECUTE IMMEDIATE 'TRUNCATE ...'
     - 2 cursores:
       (1) c_det = SYS_REFCURSOR (variable de cursor) sin parámetro
       (2) c_res = cursor explícito con parámetro (mes_anno)
     - VARRAY: v_puntos (normal + extras)
     - RECORD: v_reg
     - Cálculo de puntos en PL/SQL (IF/ELSIF), no en SELECT
     ============================================================ */

  -- A) Año a informar = año anterior al de ejecución (regla SBIF)
  v_anno_informe NUMBER := :b_anno_ejecucion - 1;

  -- B) VARRAY de puntos:
  --    índice 1 = puntos base
  --    índice 2..4 = extras según tramo anual
  TYPE t_puntos IS VARRAY(4) OF NUMBER;
  v_puntos t_puntos := t_puntos(:b_ptos_normal, :b_ptos_ext1, :b_ptos_ext2, :b_ptos_ext3);

  -- C) c_det: Variable de cursor (REF CURSOR) sin parámetro
  --    Se abrirá con OPEN ... FOR SELECT ...
  c_det SYS_REFCURSOR;

  -- D) RECORD para hacer FETCH limpio (evita muchas variables sueltas)
  TYPE r_det IS RECORD(
    numrun            CLIENTE.numrun%TYPE,
    dvrun             CLIENTE.dvrun%TYPE,
    nro_tarjeta       TARJETA_CLIENTE.nro_tarjeta%TYPE,
    nro_transaccion   TRANSACCION_TARJETA_CLIENTE.nro_transaccion%TYPE,
    fecha_transaccion TRANSACCION_TARJETA_CLIENTE.fecha_transaccion%TYPE,
    tipo_transaccion  TIPO_TRANSACCION_TARJETA.nombre_tptran_tarjeta%TYPE,
    monto_transaccion TRANSACCION_TARJETA_CLIENTE.monto_transaccion%TYPE,
    cod_tipo_cliente  CLIENTE.cod_tipo_cliente%TYPE
  );
  v_reg r_det;

  -- E) Variables para lógica de puntos (se calculan en PL/SQL)
  v_puntos_base  NUMBER := 0;  -- puntos por cada 100.000
  v_puntos_extra NUMBER := 0;  -- puntos extra según tramo anual (solo algunos clientes)
  v_puntos_total NUMBER := 0;  -- base + extra
  v_monto_anual  NUMBER := 0;  -- suma anual del cliente (año informado)
  v_es_extra     NUMBER := 0;  -- flag: 1 si aplica extra, 0 si no

  -- F) Cursor explícito parametrizado: resume por mes_anno
  --    Importante: el resumen se calcula sobre DETALLE ya cargado.
  CURSOR c_res(p_mes_anno VARCHAR2) IS
    SELECT
      p_mes_anno AS mes_anno,
      -- Compras
      SUM(CASE WHEN tipo_transaccion = 'Compras Tiendas Retail o Asociadas'
               THEN monto_transaccion ELSE 0 END) AS monto_total_compras,
      SUM(CASE WHEN tipo_transaccion = 'Compras Tiendas Retail o Asociadas'
               THEN puntos_allthebest ELSE 0 END) AS total_puntos_compras,
      -- Avances
      SUM(CASE WHEN tipo_transaccion = 'Avance en Efectivo'
               THEN monto_transaccion ELSE 0 END) AS monto_total_avances,
      SUM(CASE WHEN tipo_transaccion = 'Avance en Efectivo'
               THEN puntos_allthebest ELSE 0 END) AS total_puntos_avances,
      -- super avance
      SUM(CASE WHEN tipo_transaccion = 'Super Avance en Efectivo'
               THEN monto_transaccion ELSE 0 END) AS monto_total_savances,
      SUM(CASE WHEN tipo_transaccion = 'Super Avance en Efectivo'
               THEN puntos_allthebest ELSE 0 END) AS total_puntos_savances
    FROM DETALLE_PUNTOS_TARJETA_CATB
    WHERE TO_CHAR(fecha_transaccion,'MMYYYY') = p_mes_anno;

  -- v_res: variable tipo fila del cursor resumen
  v_res c_res%ROWTYPE;

  -- mes actual del loop de resumen
  v_mes_anno VARCHAR2(6);

BEGIN
  -- 1) TRUNCATE en ejecución: permite re-ejecutar el proceso sin duplicar
  EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_PUNTOS_TARJETA_CATB';
  EXECUTE IMMEDIATE 'TRUNCATE TABLE RESUMEN_PUNTOS_TARJETA_CATB';

  -- 2) Abrir c_det con TODAS las transacciones del año informado (año anterior)
  --    Se ordenan aquí para cumplir el orden requerido al insertar en DETALLE.
  OPEN c_det FOR
    SELECT
      c.numrun,
      c.dvrun,
      tc.nro_tarjeta,
      t.nro_transaccion,
      t.fecha_transaccion,
      tt.nombre_tptran_tarjeta AS tipo_transaccion,
      t.monto_transaccion,
      c.cod_tipo_cliente
    FROM TRANSACCION_TARJETA_CLIENTE t
    JOIN TARJETA_CLIENTE tc ON tc.nro_tarjeta = t.nro_tarjeta
    JOIN CLIENTE c         ON c.numrun      = tc.numrun
    JOIN TIPO_TRANSACCION_TARJETA tt ON tt.cod_tptran_tarjeta = t.cod_tptran_tarjeta
    WHERE EXTRACT(YEAR FROM t.fecha_transaccion) = v_anno_informe
    ORDER BY t.fecha_transaccion, c.numrun, t.nro_transaccion;

  -- 3) Recorrer c_det fila a fila (procesamiento masivo controlado)
  LOOP
    FETCH c_det INTO v_reg;
    EXIT WHEN c_det%NOTFOUND;

    -- 3.1) Puntos base: por cada 100.000 del monto solicitado -> v_puntos(1)
    v_puntos_base  := TRUNC(v_reg.monto_transaccion / 100000) * v_puntos(1);
    v_puntos_extra := 0;

    -- 3.2) Determinar si el cliente es de grupo con puntos extra
    --     IMPORTANTE: depende del texto en TIPO_CLIENTE.
    SELECT CASE
             WHEN UPPER(nombre_tipo_cliente) LIKE '%DUEA%CASA'
               OR UPPER(nombre_tipo_cliente) LIKE 'PENSIONAD%TERCERA%'
             THEN 1 ELSE 0
           END
    INTO v_es_extra
    FROM TIPO_CLIENTE
    WHERE cod_tipo_cliente = v_reg.cod_tipo_cliente;

    -- 3.3) Si aplica extra: calcular el monto anual del cliente (año informado)
    IF v_es_extra = 1 THEN
      SELECT NVL(SUM(t2.monto_transaccion),0)
      INTO v_monto_anual
      FROM TRANSACCION_TARJETA_CLIENTE t2
      JOIN TARJETA_CLIENTE tc2 ON tc2.nro_tarjeta = t2.nro_tarjeta
      WHERE tc2.numrun = v_reg.numrun
        AND EXTRACT(YEAR FROM t2.fecha_transaccion) = v_anno_informe;

      -- 3.4) Asignar puntos extra según tramo anual (paramétrico vía BIND)
      IF v_monto_anual BETWEEN :b_tramo1_inf AND :b_tramo1_sup THEN
        v_puntos_extra := TRUNC(v_reg.monto_transaccion / 100000) * v_puntos(2);
      ELSIF v_monto_anual BETWEEN :b_tramo2_inf AND :b_tramo2_sup THEN
        v_puntos_extra := TRUNC(v_reg.monto_transaccion / 100000) * v_puntos(3);
      ELSIF v_monto_anual >= :b_tramo3_inf THEN
        v_puntos_extra := TRUNC(v_reg.monto_transaccion / 100000) * v_puntos(4);
      END IF;
    END IF;

    -- 3.5) Total de puntos de esta transacción
    v_puntos_total := v_puntos_base + v_puntos_extra;

    -- 3.6) Poblar DETALLE con el resultado calculado
    INSERT INTO DETALLE_PUNTOS_TARJETA_CATB
      (numrun, dvrun, nro_tarjeta, nro_transaccion, fecha_transaccion,
       tipo_transaccion, monto_transaccion, puntos_allthebest)
    VALUES
      (v_reg.numrun, v_reg.dvrun, v_reg.nro_tarjeta, v_reg.nro_transaccion, v_reg.fecha_transaccion,
       v_reg.tipo_transaccion, v_reg.monto_transaccion, v_puntos_total);

  END LOOP;

  -- 4) Cerrar cursor (libera memoria/recursos)
  CLOSE c_det;

  -- 5) Generar resumen mensual usando cursor explícito con parámetro (c_res)
  --    Primero se obtiene la lista de meses a resumir (ordenada cronológicamente)
  FOR m IN (
    SELECT DISTINCT TO_CHAR(fecha_transaccion,'MMYYYY') AS mes_anno
    FROM DETALLE_PUNTOS_TARJETA_CATB
    ORDER BY SUBSTR(TO_CHAR(fecha_transaccion,'MMYYYY'),3,4), -- YYYY
             SUBSTR(TO_CHAR(fecha_transaccion,'MMYYYY'),1,2)  -- MM
  ) LOOP
    v_mes_anno := m.mes_anno;

    -- Abrir cursor de resumen para ese mes_anno
    OPEN c_res(v_mes_anno);
    FETCH c_res INTO v_res;
    CLOSE c_res;

    -- Insertar la fila resumen (mes_anno)
    INSERT INTO RESUMEN_PUNTOS_TARJETA_CATB
      (mes_anno, monto_total_compras, total_puntos_compras,
       monto_total_avances, total_puntos_avances,
       monto_total_savances, total_puntos_savances)
    VALUES
      (v_res.mes_anno, v_res.monto_total_compras, v_res.total_puntos_compras,
       v_res.monto_total_avances, v_res.total_puntos_avances,
       v_res.monto_total_savances, v_res.total_puntos_savances);
  END LOOP;

  -- Confirmar cambios
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('CASO 1 OK. Año informado: '||v_anno_informe);

EXCEPTION
  WHEN OTHERS THEN
    -- Si falla algo, se revierte todo
    ROLLBACK;

    -- Cierre defensivo del cursor si quedó abierto
    IF c_det%ISOPEN THEN
      CLOSE c_det;
    END IF;

    -- Mensaje de error
    DBMS_OUTPUT.PUT_LINE('ERROR CASO 1: '||SQLERRM);
END;
/

------------------------------------------------------------
-- CASO 2 — Aporte SBIF (mismo año)
-- Objetivo: procesar avances y super avances del año actual del proceso,
-- calcular aporte SBIF según tabla TRAMO_APORTE_SBIF y poblar:
-- 1) DETALLE_APORTE_SBIF
-- 2) RESUMEN_APORTE_SBIF por mes y tipo
------------------------------------------------------------

-- 1) VARIABLE BIND del año del proceso (dinámico)
VARIABLE b_anno_proceso NUMBER;
EXEC :b_anno_proceso := EXTRACT(YEAR FROM SYSDATE);

SET SERVEROUTPUT ON;

DECLARE
  /* ============================================================
     CASO 2 - APORTE SBIF (MISMO AÑO)
     Requisitos cubiertos:
     - 2 cursores explícitos (uno con parámetro) 
     - TRUNCATE en ejecución 
     - Cálculo del aporte en PL/SQL 
     ============================================================ */

  -- Año a procesar (mismo año)
  v_anno NUMBER := :b_anno_proceso;

  -- Cursor detalle: trae solo transacciones de Avance / Super Avance del año
  CURSOR c_det IS
    SELECT
      c.numrun,
      c.dvrun,
      tc.nro_tarjeta,
      t.nro_transaccion,
      t.fecha_transaccion,
      tt.nombre_tptran_tarjeta AS tipo_transaccion,
      t.monto_total_transaccion AS monto_total_transaccion
    FROM TRANSACCION_TARJETA_CLIENTE t
    JOIN TARJETA_CLIENTE tc ON tc.nro_tarjeta = t.nro_tarjeta
    JOIN CLIENTE c ON c.numrun = tc.numrun
    JOIN TIPO_TRANSACCION_TARJETA tt ON tt.cod_tptran_tarjeta = t.cod_tptran_tarjeta
    WHERE EXTRACT(YEAR FROM t.fecha_transaccion) = v_anno
      -- Filtro tipos (ojo: aquí usas "Super" sin acento para calzar con tu data)
      AND tt.nombre_tptran_tarjeta IN ('Avance en Efectivo','Super Avance en Efectivo')
    ORDER BY t.fecha_transaccion, c.numrun;

  -- Registro implícito de fila del cursor detalle
  v_reg c_det%ROWTYPE;

  -- Cursor resumen con parámetro (mes, tipo) calculado desde el detalle
  CURSOR c_res(p_mes VARCHAR2, p_tipo VARCHAR2) IS
    SELECT
      p_mes AS mes_anno,
      p_tipo AS tipo_transaccion,
      SUM(monto_transaccion) AS monto_total_transacciones,
      SUM(aporte_sbif)       AS aporte_total_abif
    FROM DETALLE_APORTE_SBIF
    WHERE TO_CHAR(fecha_transaccion,'MMYYYY') = p_mes
      AND tipo_transaccion = p_tipo;

  v_res c_res%ROWTYPE;

  -- Variables de cálculo
  v_porc   NUMBER := 0; -- porcentaje leído desde TRAMO_APORTE_SBIF
  v_aporte NUMBER := 0; -- aporte calculado para la transacción

BEGIN
  -- 1) TRUNCATE para re-ejecutabilidad
  EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_APORTE_SBIF';
  EXECUTE IMMEDIATE 'TRUNCATE TABLE RESUMEN_APORTE_SBIF';

  -- 2) Poblar tabla detalle: recorrer cada transacción del cursor c_det
  OPEN c_det;
  LOOP
    FETCH c_det INTO v_reg;
    EXIT WHEN c_det%NOTFOUND;

    -- 2.1) Buscar el % según tramo (monto_total_transaccion con interés)
    SELECT porc_aporte_sbif
    INTO  v_porc
    FROM  TRAMO_APORTE_SBIF
    WHERE v_reg.monto_total_transaccion BETWEEN tramo_inf_av_sav AND tramo_sup_av_sav;

    -- 2.2) Calcular aporte en PL/SQL (NO en SELECT)
    v_aporte := ROUND(v_reg.monto_total_transaccion * (v_porc/100));

    -- 2.3) Insertar en tabla detalle
    INSERT INTO DETALLE_APORTE_SBIF
      (numrun, dvrun, nro_tarjeta, nro_transaccion, fecha_transaccion,
       tipo_transaccion, monto_transaccion, aporte_sbif)
    VALUES
      (v_reg.numrun, v_reg.dvrun, v_reg.nro_tarjeta, v_reg.nro_transaccion, v_reg.fecha_transaccion,
       v_reg.tipo_transaccion, v_reg.monto_total_transaccion, v_aporte);
  END LOOP;

  -- Cerrar cursor detalle
  CLOSE c_det;

  -- 3) Poblar resumen (mes + tipo) usando cursor parametrizado c_res
  FOR x IN (
    SELECT DISTINCT
      TO_CHAR(fecha_transaccion,'MMYYYY') AS mes_anno,
      tipo_transaccion
    FROM DETALLE_APORTE_SBIF
    ORDER BY SUBSTR(TO_CHAR(fecha_transaccion,'MMYYYY'),3,4), -- YYYY
             SUBSTR(TO_CHAR(fecha_transaccion,'MMYYYY'),1,2), -- MM
             tipo_transaccion
  ) LOOP
    OPEN c_res(x.mes_anno, x.tipo_transaccion);
    FETCH c_res INTO v_res;
    CLOSE c_res;

    INSERT INTO RESUMEN_APORTE_SBIF
      (mes_anno, tipo_transaccion, monto_total_transacciones, aporte_total_abif)
    VALUES
      (v_res.mes_anno, v_res.tipo_transaccion, v_res.monto_total_transacciones, v_res.aporte_total_abif);
  END LOOP;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('CASO 2 OK. Año procesado: '||v_anno);

EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    IF c_det%ISOPEN THEN CLOSE c_det; END IF;
    DBMS_OUTPUT.PUT_LINE('ERROR CASO 2: '||SQLERRM);
END;
/

-- CASO 1: detalle y resumen
SELECT * FROM DETALLE_PUNTOS_TARJETA_CATB
ORDER BY fecha_transaccion, numrun, nro_transaccion;

SELECT * FROM RESUMEN_PUNTOS_TARJETA_CATB
ORDER BY SUBSTR(mes_anno,3,4), SUBSTR(mes_anno,1,2);  -- YYYY luego MM

-- CASO 2: detalle y resumen
SELECT * FROM DETALLE_APORTE_SBIF
ORDER BY fecha_transaccion, numrun;

SELECT * FROM RESUMEN_APORTE_SBIF
ORDER BY SUBSTR(mes_anno,3,4), SUBSTR(mes_anno,1,2), tipo_transaccion;
