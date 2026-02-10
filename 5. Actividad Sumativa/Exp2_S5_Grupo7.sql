-- 1. Variables BIND (parametricas)

SET SERVEROUTPUT ON; -- Habilita cer mensajes DBMS_OUTPUT 

-- Año de ejecución: se obtiene desde la fecha del sistema
-- Ejemplo: si hoy es 2026, :b_anno_ejecucion = 2026
VARIABLE b_anno_ejecucion NUMBER;
EXEC :b_anno_ejecucion := EXTRACT(YEAR FROM SYSDATE); -- Asignacion de varible Bind(EXEC) y EXTRACT devuelve año actual en numero

--2. Bloque PL/SQL Anonimo (CASO SBIF)

DECLARE
 ---------------------------------------------------------------
    -- CASO: APORTE SBIF - Avances y Super Avances
    -- Genera DETALLE_APORTE_SBIF y RESUMEN_APORTE_SBIF
    -- Año a informar = (:b_anno_ejecucion - 1)
 ---------------------------------------------------------------

  -- (n) Periodo paramétrico
  v_anno_informe NUMBER := :b_anno_ejecucion - 1;

  -- (k) VARRAY con tipos de transacción a procesar
  TYPE t_varray_tipos IS VARRAY(2) OF VARCHAR2(50);
  v_tipos t_varray_tipos := t_varray_tipos(
    'Avance en Efectivo',
    q'[Super Avance en Efectivo]'
  );

  -- Variables de proceso
  v_porc_aporte  TRAMO_APORTE_SBIF.porc_aporte_sbif%TYPE; -- %TYPE toma el tipo de dato exacto desde la columna real
  v_aporte       NUMBER(10);
  v_total_regs   NUMBER := 0;   -- total a procesar
  v_procesadas   NUMBER := 0;   -- contador iteraciones OK

  -- EXCEPCIONES:

  -- (j) Excepcion definida por el usuario (control de commit)
  e_iteraciones_incompletas EXCEPTION;

  -- (j) Excepción NO predefinida (ej: tabla inexistente en TRUNCATE)
  e_tabla_no_existe EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_tabla_no_existe, -942); -- ORA-00942

 ---------------------------------------------------------------
    -- (b)(c) CURSOR 1: DETALLE (explicito, SIN parametro)
    -- Trae cada transaccion del año a informar
    -- Solo tipos en v_tipos (avance y super avance)
    -- Orden: fecha_transaccion asc, numrun asc
 ---------------------------------------------------------------
  CURSOR c_det IS
    SELECT
      c.numrun,
      c.dvrun,
      tc.nro_tarjeta,
      ttc.nro_transaccion,
      ttc.fecha_transaccion,
      ttt.nombre_tptran_tarjeta AS tipo_transaccion,
      ttc.monto_total_transaccion AS monto_total_transaccion
    FROM transaccion_tarjeta_cliente ttc
    JOIN tarjeta_cliente tc
      ON tc.nro_tarjeta = ttc.nro_tarjeta
    JOIN cliente c
      ON c.numrun = tc.numrun
    JOIN tipo_transaccion_tarjeta ttt
      ON ttt.cod_tptran_tarjeta = ttc.cod_tptran_tarjeta
    WHERE EXTRACT(YEAR FROM ttc.fecha_transaccion) = v_anno_informe
      AND ttt.nombre_tptran_tarjeta IN (v_tipos(1), v_tipos(2))
    ORDER BY ttc.fecha_transaccion ASC, c.numrun ASC;

  -- (l) Registro PL/SQL
  -- %ROWTYPE crea un registro con todas ls columnas del cursor
  -- r_det.numrun, r_det.dvrun, etc
  r_det c_det%ROWTYPE;

 ---------------------------------------------------------------
     -- (b)(c) CURSOR 2: RESUMEN (explicito CON parametro)
     -- Se alimenta desde DETALLE_APORTE_SBIF (ya calculado con aporte)
     -- Agrupa por mes-año y tipo
     -- Orden: mes_anno asc, tipo_transaccion asc
 ---------------------------------------------------------------
  CURSOR c_res (p_anno NUMBER) IS
    SELECT
      TO_CHAR(fecha_transaccion, 'MMYYYY') AS mes_anno,
      tipo_transaccion,
      SUM(monto_transaccion) AS monto_total_transacciones,
      SUM(aporte_sbif)       AS aporte_total_abif
    FROM detalle_aporte_sbif
    WHERE EXTRACT(YEAR FROM fecha_transaccion) = p_anno
    GROUP BY TO_CHAR(fecha_transaccion, 'MMYYYY'), tipo_transaccion
    ORDER BY TO_CHAR(fecha_transaccion, 'MMYYYY') ASC, tipo_transaccion ASC;

BEGIN
  -- Mensaje inicial (para visualizar)
  DBMS_OUTPUT.PUT_LINE('=== PROCESO SBIF - Año a informar: ' || v_anno_informe || ' ===');

  -- (g) TRUNCATE en runtime
  -- Limpia tablas destino para permitir reejecucion del bloque
  -- TRUNCATE es DDL: borra rapido y reinicia HWM
  EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_APORTE_SBIF';
  EXECUTE IMMEDIATE 'TRUNCATE TABLE RESUMEN_APORTE_SBIF';

  -- Total de registros a procesar (para commit controlado) 
  SELECT COUNT(*)
  INTO v_total_regs
  FROM transaccion_tarjeta_cliente ttc
  JOIN tipo_transaccion_tarjeta ttt
    ON ttt.cod_tptran_tarjeta = ttc.cod_tptran_tarjeta
  WHERE EXTRACT(YEAR FROM ttc.fecha_transaccion) = v_anno_informe
    AND ttt.nombre_tptran_tarjeta IN (v_tipos(1), v_tipos(2));

  DBMS_OUTPUT.PUT_LINE('Total transacciones a procesar: ' || v_total_regs);

 ---------------------------------------------------------------
     -- 1. Generacion DETALLE
     -- (h) aporte calculado en PL/SQL (NO en el SELECT)
 ---------------------------------------------------------------
  OPEN c_det;
  LOOP
    FETCH c_det INTO r_det;
    EXIT WHEN c_det%NOTFOUND;

    -- Buscar porcentaje segun tramo (tabla TRAMO_APORTE_SBIF)
     -- Se usa BETWEEN: si el monto cae dentro de un tramo, tomamos el %
    BEGIN
      SELECT porc_aporte_sbif
      INTO v_porc_aporte
      FROM tramo_aporte_sbif
      WHERE r_det.monto_total_transaccion BETWEEN tramo_inf_av_sav AND tramo_sup_av_sav;

    EXCEPTION
      -- (j) Excepcion predefinida: NO_DATA_FOUND 
      WHEN NO_DATA_FOUND THEN
        -- Si no existe tramo, se fuerza 0% (y queda documentado)
        v_porc_aporte := 0;
    END;

    -- (1) redondeo a entero
    -- aporte = monto_total * (porcentaje / 100)
    -- ROUND elimina decimales dejando entero
    v_aporte := ROUND(r_det.monto_total_transaccion * (v_porc_aporte / 100));

    -- Insert DETALLE_APORTE_SBIF
    -- Guarda transacción + aporte calculado
    INSERT INTO detalle_aporte_sbif
      (numrun, dvrun, nro_tarjeta, nro_transaccion, fecha_transaccion,
       tipo_transaccion, monto_transaccion, aporte_sbif)
    VALUES
      (r_det.numrun, r_det.dvrun, r_det.nro_tarjeta, r_det.nro_transaccion, r_det.fecha_transaccion,
       r_det.tipo_transaccion, r_det.monto_total_transaccion, v_aporte);
    
    -- Contador de iteraciones exitosas
    v_procesadas := v_procesadas + 1;
  END LOOP;
  CLOSE c_det; -- cierra el cursor

  DBMS_OUTPUT.PUT_LINE('Detalle generado. Procesadas: ' || v_procesadas);

 ---------------------------------------------------------------
     -- 2. Generacion RESUMEN (desde detalle ya calculado)
     -- Se usa el cursor con parámetro p_anno
     -- Agrupa el detalle por mes y tipo y lo inserta en RESUMEN
 ---------------------------------------------------------------
  FOR r_res IN c_res(v_anno_informe) LOOP
    INSERT INTO resumen_aporte_sbif
      (mes_anno, tipo_transaccion, monto_total_transacciones, aporte_total_abif)
    VALUES
      (r_res.mes_anno, r_res.tipo_transaccion, r_res.monto_total_transacciones, r_res.aporte_total_abif);
  END LOOP;

  -- (m) COMMIT solo si terminó OK y procesó todo
  -- Solo se confirma si procesamos EXACTAMENTE el total esperado
  IF v_procesadas = v_total_regs THEN
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('COMMIT OK. Registros confirmados.');
  ELSE
    ROLLBACK;
    -- Disparamos excepción definida por usuario
    RAISE e_iteraciones_incompletas;
  END IF;

EXCEPTION
  -- (j) Excepción definida por el usuario 
  WHEN e_iteraciones_incompletas THEN
    DBMS_OUTPUT.PUT_LINE('ERROR: Iteraciones incompletas. Se hizo ROLLBACK.');

  -- (j) Excepcion NO predefinida (PRAGMA) 
  -- Si una tabla no existe al TRUNCATE, cae aquí
  WHEN e_tabla_no_existe THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('ERROR ORA-00942: Tabla no existe al TRUNCATE. Se hizo ROLLBACK.');

  -- Cualquier otro error 
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('ERROR GENERAL: ' || SQLCODE || ' - ' || SQLERRM);
END;
/

-- 3. Consultas de verificacion 

SELECT *
FROM detalle_aporte_sbif
ORDER BY fecha_transaccion ASC, numrun ASC;

SELECT *
FROM resumen_aporte_sbif
ORDER BY mes_anno ASC, tipo_transaccion ASC;