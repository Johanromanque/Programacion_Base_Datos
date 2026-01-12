/* ============================================================
   BANK SOLUTIONS - Formativa 1
   ============================================================ */

---------------------------------------------------------------
-- CASO 1: CLIENTE_TODOSUMA (5 ejecuciones: 5 clientes)
-- Objetivo:
--   - Calcular los Pesos TODOSUMA según créditos otorgados el año anterior.
--   - Guardar el resultado en la tabla CLIENTE_TODOSUMA.
-- Reglas:
--   - RUN del cliente entra por enlace BIND (:b_run_cliente).
--   - Tramos y valores de pesos entran por BIND (paramétricos).
--   - Año anterior se obtiene con funciones de fecha (sin fechas fijas).
--   - Cálculos se hacen en PL/SQL (NO en el SELECT) usando IF/ELSIF.
---------------------------------------------------------------

-- Enlace BIND (variables externas al bloque pl/sql)
-- RUN del cliente a procesar (se setea antes de cada ejecución).
VAR b_run_cliente      VARCHAR2(15);

-- Tramos para calcular pesos extras (solo aplica a Trabajadores independientes).
VAR b_tramo1_max       NUMBER;  -- ejemplo 1.000.000
VAR b_tramo2_max       NUMBER;  -- ejemlpo 3.000.000

-- Valores por cada 100.000
VAR b_peso_normal_100k NUMBER;  -- 1.200 por cada 100.000
VAR b_extra_t1_100k    NUMBER;  -- +100 por cada 100.000 (tramo 1)
VAR b_extra_t2_100k    NUMBER;  -- +300 por cada 100.000 (tramo 2)
VAR b_extra_t3_100k    NUMBER;  -- +550 por cada 100.000 (tramo 3)

-- Asignación de parámetros (se hace una vez) 
BEGIN
  -- Tramos (paramétricos)
  :b_tramo1_max       := 1000000;
  :b_tramo2_max       := 3000000;

  -- Pesos base y extras (paramétricos)
  :b_peso_normal_100k := 1200;
  :b_extra_t1_100k    := 100;
  :b_extra_t2_100k    := 300;
  :b_extra_t3_100k    := 550;
END;
/
---------------------------------------------------------------
-- BLOQUE CASO 1 (se ejecuta 5 veces, una por cliente)
---------------------------------------------------------------


-- 1 KAREN (RUN 21.242.003-4)

BEGIN
  -- BIND paramétrico del cliente a procesar
  :b_run_cliente := '21242003-4';
END;
/
DECLARE
  -- Rango del año anterior (dinámico):
  -- v_ini_ano_ant = 01-01 del año anterior
  -- v_fin_ano_ant = 31-12 del año anterior
  v_ini_ano_ant DATE := TRUNC(ADD_MONTHS(SYSDATE, -12), 'YYYY');
  v_ini_ano_act DATE := TRUNC(SYSDATE, 'YYYY');
  v_fin_ano_ant DATE := v_ini_ano_act - 1;

  -- Datos del cliente (se recuperan por SELECT INTO)
  v_nro_cliente     CLIENTE.NRO_CLIENTE%TYPE;
  v_run_cliente     VARCHAR2(15);
  v_nombre_cliente  VARCHAR2(100);
  v_tipo_cliente    VARCHAR2(100);

  -- Variables de cálculo (todo en PL/SQL)
  v_monto_anual     NUMBER := 0; -- suma de montos solicitados del año anterior
  v_unidades_100k   NUMBER := 0; -- cuántas veces cabe 100.000 en el monto anual
  v_pesos_normales  NUMBER := 0; -- pesos base = unidades_100k * 1200
  v_extra_100k      NUMBER := 0; -- extra por cada 100.000 según tramo (solo independientes)
  v_pesos_extras    NUMBER := 0; -- unidades_100k * extra_100k
  v_pesos_total     NUMBER := 0; -- pesos_normales + pesos_extras
BEGIN
  ----------------------------------------------------------------
  -- (SQL 1) Obtener datos del cliente a partir del RUN paramétrico
  --        Se arma RUN como "numrun-dvrun" para comparar con :b_run_cliente.
  ----------------------------------------------------------------
  SELECT c.nro_cliente,
         TO_CHAR(c.numrun) || '-' || c.dvrun,
         RTRIM(c.pnombre || ' ' || NVL(c.snombre || ' ', '') ||
               c.appaterno || ' ' || NVL(c.apmaterno, '')),
         tc.nombre_tipo_cliente
  INTO   v_nro_cliente, v_run_cliente, v_nombre_cliente, v_tipo_cliente
  FROM   cliente c
  JOIN   tipo_cliente tc ON tc.cod_tipo_cliente = c.cod_tipo_cliente
  WHERE  TO_CHAR(c.numrun) || '-' || c.dvrun = :b_run_cliente;

  ----------------------------------------------------------------
  -- (SQL 2) Sumar todos los montos solicitados del AÑO ANTERIOR
  --        NVL para que si no hay créditos, quede 0.
  ----------------------------------------------------------------
  SELECT NVL(SUM(cc.monto_solicitado), 0)
  INTO   v_monto_anual
  FROM   credito_cliente cc
  WHERE  cc.nro_cliente = v_nro_cliente
  AND    cc.fecha_otorga_cred >= v_ini_ano_ant
  AND    cc.fecha_otorga_cred <= v_fin_ano_ant;

  ----------------------------------------------------------------
  -- (PL/SQL) Cálculo de unidades de 100.000 y pesos normales
  -- TRUNC: si monto=250.000 => unidades_100k=2 (no 2,5)
  ----------------------------------------------------------------
  v_unidades_100k  := TRUNC(v_monto_anual / 100000);
  v_pesos_normales := v_unidades_100k * :b_peso_normal_100k;

  ----------------------------------------------------------------
  -- (PL/SQL) Pesos extras SOLO si el tipo es "Trabajadores independientes"
  -- Se determina el extra_100k según tramo de v_monto_anual (IF/ELSIF)
  ----------------------------------------------------------------
  IF UPPER(v_tipo_cliente) = UPPER('Trabajadores independientes') THEN

    IF v_monto_anual < :b_tramo1_max THEN
      v_extra_100k := :b_extra_t1_100k;
    ELSIF v_monto_anual <= :b_tramo2_max THEN
      v_extra_100k := :b_extra_t2_100k;
    ELSE
      v_extra_100k := :b_extra_t3_100k;
    END IF;

    v_pesos_extras := v_unidades_100k * v_extra_100k;

  ELSE
    v_pesos_extras := 0;
  END IF;

  -- Total final
  v_pesos_total := v_pesos_normales + v_pesos_extras;

  ----------------------------------------------------------------
  -- (SQL 3) Si existe el cliente en CLIENTE_TODOSUMA, se elimina para re-ejecutar
  ----------------------------------------------------------------
  DELETE FROM cliente_todosuma
  WHERE nro_cliente = v_nro_cliente;

  ----------------------------------------------------------------
  -- (SQL 4) Insertar resultado final en CLIENTE_TODOSUMA
  ----------------------------------------------------------------
  INSERT INTO cliente_todosuma
    (nro_cliente, run_cliente, nombre_cliente, tipo_cliente,
     monto_solic_creditos, monto_pesos_todosuma)
  VALUES
    (v_nro_cliente, v_run_cliente, v_nombre_cliente, v_tipo_cliente,
     v_monto_anual, v_pesos_total);

  -- Confirmar cambios
  COMMIT;

END;
/


-- 2) SILVANA

BEGIN :b_run_cliente := '22176845-2'; END;
/
DECLARE
  -- (mismo bloque, mismas reglas)
  v_ini_ano_ant DATE := TRUNC(ADD_MONTHS(SYSDATE, -12), 'YYYY');
  v_ini_ano_act DATE := TRUNC(SYSDATE, 'YYYY');
  v_fin_ano_ant DATE := v_ini_ano_act - 1;

  v_nro_cliente     CLIENTE.NRO_CLIENTE%TYPE;
  v_run_cliente     VARCHAR2(15);
  v_nombre_cliente  VARCHAR2(100);
  v_tipo_cliente    VARCHAR2(100);

  v_monto_anual     NUMBER := 0;
  v_unidades_100k   NUMBER := 0;
  v_pesos_normales  NUMBER := 0;
  v_extra_100k      NUMBER := 0;
  v_pesos_extras    NUMBER := 0;
  v_pesos_total     NUMBER := 0;
BEGIN
  -- SQL 1: datos cliente
  SELECT c.nro_cliente,
         TO_CHAR(c.numrun) || '-' || c.dvrun,
         RTRIM(c.pnombre || ' ' || NVL(c.snombre || ' ', '') || c.appaterno || ' ' || NVL(c.apmaterno, '')),
         tc.nombre_tipo_cliente
  INTO   v_nro_cliente, v_run_cliente, v_nombre_cliente, v_tipo_cliente
  FROM   cliente c
  JOIN   tipo_cliente tc ON tc.cod_tipo_cliente = c.cod_tipo_cliente
  WHERE  TO_CHAR(c.numrun) || '-' || c.dvrun = :b_run_cliente;

  -- SQL 2: suma créditos año anterior
  SELECT NVL(SUM(cc.monto_solicitado), 0)
  INTO   v_monto_anual
  FROM   credito_cliente cc
  WHERE  cc.nro_cliente = v_nro_cliente
  AND    cc.fecha_otorga_cred >= v_ini_ano_ant
  AND    cc.fecha_otorga_cred <= v_fin_ano_ant;

  -- PL/SQL: cálculo base
  v_unidades_100k  := TRUNC(v_monto_anual / 100000);
  v_pesos_normales := v_unidades_100k * :b_peso_normal_100k;

  -- PL/SQL: extras solo independientes
  IF UPPER(v_tipo_cliente) = UPPER('Trabajadores independientes') THEN
    IF v_monto_anual < :b_tramo1_max THEN
      v_extra_100k := :b_extra_t1_100k;
    ELSIF v_monto_anual <= :b_tramo2_max THEN
      v_extra_100k := :b_extra_t2_100k;
    ELSE
      v_extra_100k := :b_extra_t3_100k;
    END IF;
    v_pesos_extras := v_unidades_100k * v_extra_100k;
  ELSE
    v_pesos_extras := 0;
  END IF;

  v_pesos_total := v_pesos_normales + v_pesos_extras;

  -- SQL 3/4: refresh + insert
  DELETE FROM cliente_todosuma WHERE nro_cliente = v_nro_cliente;

  INSERT INTO cliente_todosuma
    (nro_cliente, run_cliente, nombre_cliente, tipo_cliente,
     monto_solic_creditos, monto_pesos_todosuma)
  VALUES
    (v_nro_cliente, v_run_cliente, v_nombre_cliente, v_tipo_cliente,
     v_monto_anual, v_pesos_total);

  COMMIT;
END;
/

-- 3 DENISSE
BEGIN :b_run_cliente := '18858542-6'; END;
/
DECLARE
  v_ini_ano_ant DATE := TRUNC(ADD_MONTHS(SYSDATE, -12), 'YYYY');
  v_ini_ano_act DATE := TRUNC(SYSDATE, 'YYYY');
  v_fin_ano_ant DATE := v_ini_ano_act - 1;

  v_nro_cliente     CLIENTE.NRO_CLIENTE%TYPE;
  v_run_cliente     VARCHAR2(15);
  v_nombre_cliente  VARCHAR2(100);
  v_tipo_cliente    VARCHAR2(100);

  v_monto_anual     NUMBER := 0;
  v_unidades_100k   NUMBER := 0;
  v_pesos_normales  NUMBER := 0;
  v_extra_100k      NUMBER := 0;
  v_pesos_extras    NUMBER := 0;
  v_pesos_total     NUMBER := 0;
BEGIN
  SELECT c.nro_cliente,
         TO_CHAR(c.numrun) || '-' || c.dvrun,
         RTRIM(c.pnombre || ' ' || NVL(c.snombre || ' ', '') || c.appaterno || ' ' || NVL(c.apmaterno, '')),
         tc.nombre_tipo_cliente
  INTO   v_nro_cliente, v_run_cliente, v_nombre_cliente, v_tipo_cliente
  FROM   cliente c
  JOIN   tipo_cliente tc ON tc.cod_tipo_cliente = c.cod_tipo_cliente
  WHERE  TO_CHAR(c.numrun) || '-' || c.dvrun = :b_run_cliente;

  SELECT NVL(SUM(cc.monto_solicitado), 0)
  INTO   v_monto_anual
  FROM   credito_cliente cc
  WHERE  cc.nro_cliente = v_nro_cliente
  AND    cc.fecha_otorga_cred >= v_ini_ano_ant
  AND    cc.fecha_otorga_cred <= v_fin_ano_ant;

  v_unidades_100k  := TRUNC(v_monto_anual / 100000);
  v_pesos_normales := v_unidades_100k * :b_peso_normal_100k;

  IF UPPER(v_tipo_cliente) = UPPER('Trabajadores independientes') THEN
    IF v_monto_anual < :b_tramo1_max THEN
      v_extra_100k := :b_extra_t1_100k;
    ELSIF v_monto_anual <= :b_tramo2_max THEN
      v_extra_100k := :b_extra_t2_100k;
    ELSE
      v_extra_100k := :b_extra_t3_100k;
    END IF;
    v_pesos_extras := v_unidades_100k * v_extra_100k;
  ELSE
    v_pesos_extras := 0;
  END IF;

  v_pesos_total := v_pesos_normales + v_pesos_extras;

  DELETE FROM cliente_todosuma WHERE nro_cliente = v_nro_cliente;

  INSERT INTO cliente_todosuma
    (nro_cliente, run_cliente, nombre_cliente, tipo_cliente,
     monto_solic_creditos, monto_pesos_todosuma)
  VALUES
    (v_nro_cliente, v_run_cliente, v_nombre_cliente, v_tipo_cliente,
     v_monto_anual, v_pesos_total);

  COMMIT;
END;
/

-- 4 AMANDA
BEGIN :b_run_cliente := '22558061-8'; END;
/
DECLARE
  v_ini_ano_ant DATE := TRUNC(ADD_MONTHS(SYSDATE, -12), 'YYYY');
  v_ini_ano_act DATE := TRUNC(SYSDATE, 'YYYY');
  v_fin_ano_ant DATE := v_ini_ano_act - 1;

  v_nro_cliente     CLIENTE.NRO_CLIENTE%TYPE;
  v_run_cliente     VARCHAR2(15);
  v_nombre_cliente  VARCHAR2(100);
  v_tipo_cliente    VARCHAR2(100);

  v_monto_anual     NUMBER := 0;
  v_unidades_100k   NUMBER := 0;
  v_pesos_normales  NUMBER := 0;
  v_extra_100k      NUMBER := 0;
  v_pesos_extras    NUMBER := 0;
  v_pesos_total     NUMBER := 0;
BEGIN
  SELECT c.nro_cliente,
         TO_CHAR(c.numrun) || '-' || c.dvrun,
         RTRIM(c.pnombre || ' ' || NVL(c.snombre || ' ', '') || c.appaterno || ' ' || NVL(c.apmaterno, '')),
         tc.nombre_tipo_cliente
  INTO   v_nro_cliente, v_run_cliente, v_nombre_cliente, v_tipo_cliente
  FROM   cliente c
  JOIN   tipo_cliente tc ON tc.cod_tipo_cliente = c.cod_tipo_cliente
  WHERE  TO_CHAR(c.numrun) || '-' || c.dvrun = :b_run_cliente;

  SELECT NVL(SUM(cc.monto_solicitado), 0)
  INTO   v_monto_anual
  FROM   credito_cliente cc
  WHERE  cc.nro_cliente = v_nro_cliente
  AND    cc.fecha_otorga_cred >= v_ini_ano_ant
  AND    cc.fecha_otorga_cred <= v_fin_ano_ant;

  v_unidades_100k  := TRUNC(v_monto_anual / 100000);
  v_pesos_normales := v_unidades_100k * :b_peso_normal_100k;

  IF UPPER(v_tipo_cliente) = UPPER('Trabajadores independientes') THEN
    IF v_monto_anual < :b_tramo1_max THEN
      v_extra_100k := :b_extra_t1_100k;
    ELSIF v_monto_anual <= :b_tramo2_max THEN
      v_extra_100k := :b_extra_t2_100k;
    ELSE
      v_extra_100k := :b_extra_t3_100k;
    END IF;
    v_pesos_extras := v_unidades_100k * v_extra_100k;
  ELSE
    v_pesos_extras := 0;
  END IF;

  v_pesos_total := v_pesos_normales + v_pesos_extras;

  DELETE FROM cliente_todosuma WHERE nro_cliente = v_nro_cliente;

  INSERT INTO cliente_todosuma
    (nro_cliente, run_cliente, nombre_cliente, tipo_cliente,
     monto_solic_creditos, monto_pesos_todosuma)
  VALUES
    (v_nro_cliente, v_run_cliente, v_nombre_cliente, v_tipo_cliente,
     v_monto_anual, v_pesos_total);

  COMMIT;
END;
/

-- 5 LUIS
BEGIN :b_run_cliente := '21300628-2'; END;
/
DECLARE
  v_ini_ano_ant DATE := TRUNC(ADD_MONTHS(SYSDATE, -12), 'YYYY');
  v_ini_ano_act DATE := TRUNC(SYSDATE, 'YYYY');
  v_fin_ano_ant DATE := v_ini_ano_act - 1;

  v_nro_cliente     CLIENTE.NRO_CLIENTE%TYPE;
  v_run_cliente     VARCHAR2(15);
  v_nombre_cliente  VARCHAR2(100);
  v_tipo_cliente    VARCHAR2(100);

  v_monto_anual     NUMBER := 0;
  v_unidades_100k   NUMBER := 0;
  v_pesos_normales  NUMBER := 0;
  v_extra_100k      NUMBER := 0;
  v_pesos_extras    NUMBER := 0;
  v_pesos_total     NUMBER := 0;
BEGIN
  SELECT c.nro_cliente,
         TO_CHAR(c.numrun) || '-' || c.dvrun,
         RTRIM(c.pnombre || ' ' || NVL(c.snombre || ' ', '') || c.appaterno || ' ' || NVL(c.apmaterno, '')),
         tc.nombre_tipo_cliente
  INTO   v_nro_cliente, v_run_cliente, v_nombre_cliente, v_tipo_cliente
  FROM   cliente c
  JOIN   tipo_cliente tc ON tc.cod_tipo_cliente = c.cod_tipo_cliente
  WHERE  TO_CHAR(c.numrun) || '-' || c.dvrun = :b_run_cliente;

  SELECT NVL(SUM(cc.monto_solicitado), 0)
  INTO   v_monto_anual
  FROM   credito_cliente cc
  WHERE  cc.nro_cliente = v_nro_cliente
  AND    cc.fecha_otorga_cred >= v_ini_ano_ant
  AND    cc.fecha_otorga_cred <= v_fin_ano_ant;

  v_unidades_100k  := TRUNC(v_monto_anual / 100000);
  v_pesos_normales := v_unidades_100k * :b_peso_normal_100k;

  IF UPPER(v_tipo_cliente) = UPPER('Trabajadores independientes') THEN
    IF v_monto_anual < :b_tramo1_max THEN
      v_extra_100k := :b_extra_t1_100k;
    ELSIF v_monto_anual <= :b_tramo2_max THEN
      v_extra_100k := :b_extra_t2_100k;
    ELSE
      v_extra_100k := :b_extra_t3_100k;
    END IF;
    v_pesos_extras := v_unidades_100k * v_extra_100k;
  ELSE
    v_pesos_extras := 0;
  END IF;

  v_pesos_total := v_pesos_normales + v_pesos_extras;

  DELETE FROM cliente_todosuma WHERE nro_cliente = v_nro_cliente;

  INSERT INTO cliente_todosuma
    (nro_cliente, run_cliente, nombre_cliente, tipo_cliente,
     monto_solic_creditos, monto_pesos_todosuma)
  VALUES
    (v_nro_cliente, v_run_cliente, v_nombre_cliente, v_tipo_cliente,
     v_monto_anual, v_pesos_total);

  COMMIT;
END;
/

-- Evidencia CASO 1 en tabla
SELECT * FROM cliente_todosuma ORDER BY nro_cliente;

---------------------------------------------------------------
-- CASO 2: POSTERGACIÓN DE CUOTAS (3 ejecuciones)
-- Objetivo:
--   - Crear nuevas cuotas correlativas a partir de la última cuota del crédito.
--   - Fecha vencimiento nueva = mes(es) siguiente(s) a la última fecha.
--   - Valor cuota nueva = valor_última_cuota * (1 + tasa).
--   - Si el cliente tuvo >1 crédito el año anterior: se “paga” la última cuota original.
-- Reglas:
--   - Nro cliente, solicitud y cantidad cuotas a postergar entran por BIND.
--   - Cálculos y lógica se realizan en PL/SQL (IF y LOOP).
---------------------------------------------------------------

-- BINDs CASO 2
VAR b_nro_cliente       NUMBER;
VAR b_nro_solic_credito NUMBER;
VAR b_cant_postergar    NUMBER;

---------------------------------------------------------------
-- 1 SEBASTIAN QUINTANA: cliente 5, solicitud 2001, postergar 2
---------------------------------------------------------------
BEGIN
  :b_nro_cliente       := 5;
  :b_nro_solic_credito := 2001;
  :b_cant_postergar    := 2;
END;
/
DECLARE
  -- Año anterior dinámico (mismo criterio del Caso 1)
  v_ini_ano_ant DATE := TRUNC(ADD_MONTHS(SYSDATE, -12), 'YYYY');
  v_ini_ano_act DATE := TRUNC(SYSDATE, 'YYYY');
  v_fin_ano_ant DATE := v_ini_ano_act - 1;

  -- Nombre del tipo de crédito (para decidir la tasa)
  v_nombre_credito  CREDITO.NOMBRE_CREDITO%TYPE;

  -- Datos de la última cuota del crédito
  v_ult_nro_cuota   CUOTA_CREDITO_CLIENTE.NRO_CUOTA%TYPE;
  v_ult_fecha_venc  CUOTA_CREDITO_CLIENTE.FECHA_VENC_CUOTA%TYPE;
  v_ult_valor_cuota CUOTA_CREDITO_CLIENTE.VALOR_CUOTA%TYPE;

  -- Tasa de postergación según tipo de crédito y cantidad
  v_tasa_post NUMBER := 0;

  -- Cantidad de créditos del año anterior (condición para condonar última cuota)
  v_cant_creditos_ano_ant NUMBER := 0;

  -- Variables para insertar nuevas cuotas
  v_nuevo_nro_cuota  NUMBER;
  v_nueva_fecha_venc DATE;
  v_nuevo_valor      NUMBER;
BEGIN
  ----------------------------------------------------------------
  -- (SQL 1) Obtener tipo/nombre del crédito según solicitud y cliente
  ----------------------------------------------------------------
  SELECT cr.nombre_credito
  INTO   v_nombre_credito
  FROM   credito_cliente cc
  JOIN   credito cr ON cr.cod_credito = cc.cod_credito
  WHERE  cc.nro_solic_credito = :b_nro_solic_credito
  AND    cc.nro_cliente       = :b_nro_cliente;

  ----------------------------------------------------------------
  -- (SQL 2) Obtener el número de la última cuota del crédito
  ----------------------------------------------------------------
  SELECT MAX(nro_cuota)
  INTO   v_ult_nro_cuota
  FROM   cuota_credito_cliente
  WHERE  nro_solic_credito = :b_nro_solic_credito;

  ----------------------------------------------------------------
  -- (SQL 3) Obtener fecha vencimiento y valor de esa última cuota
  ----------------------------------------------------------------
  SELECT fecha_venc_cuota, valor_cuota
  INTO   v_ult_fecha_venc, v_ult_valor_cuota
  FROM   cuota_credito_cliente
  WHERE  nro_solic_credito = :b_nro_solic_credito
  AND    nro_cuota         = v_ult_nro_cuota;

  ----------------------------------------------------------------
  -- (PL/SQL) Determinar tasa según reglas del enunciado
  ----------------------------------------------------------------
  IF UPPER(v_nombre_credito) LIKE UPPER('%Hipotec%') THEN
    -- Hipotecario: 1 cuota sin interés; 2 cuotas con 0.5%
    IF :b_cant_postergar = 1 THEN
      v_tasa_post := 0;
    ELSE
      v_tasa_post := 0.005;
    END IF;
  ELSIF UPPER(v_nombre_credito) LIKE UPPER('%Consumo%') THEN
    v_tasa_post := 0.01;
  ELSIF UPPER(v_nombre_credito) LIKE UPPER('%Automo%') THEN
    v_tasa_post := 0.02;
  ELSE
    v_tasa_post := 0;
  END IF;

  ----------------------------------------------------------------
  -- (SQL 4) Contar créditos del cliente en el año anterior
  ----------------------------------------------------------------
  SELECT COUNT(*)
  INTO   v_cant_creditos_ano_ant
  FROM   credito_cliente cc
  WHERE  cc.nro_cliente = :b_nro_cliente
  AND    cc.fecha_otorga_cred >= v_ini_ano_ant
  AND    cc.fecha_otorga_cred <= v_fin_ano_ant;

  ----------------------------------------------------------------
  -- (PL/SQL + SQL 5) Si tuvo >1 crédito en el año anterior, se condona
  --                 la última cuota original: se marca como pagada.
  ----------------------------------------------------------------
  IF v_cant_creditos_ano_ant > 1 THEN
    UPDATE cuota_credito_cliente
    SET    fecha_pago_cuota = fecha_venc_cuota,
           monto_pagado     = valor_cuota,
           saldo_por_pagar  = 0
    WHERE  nro_solic_credito = :b_nro_solic_credito
    AND    nro_cuota         = v_ult_nro_cuota;
  END IF;

  ----------------------------------------------------------------
  -- (PL/SQL LOOP + INSERT) Crear las nuevas cuotas postergadas
  -- - nro_cuota correlativo desde la última
  -- - fecha vencimiento sumando meses a la última fecha
  -- - valor cuota con interés según tasa
  -- - campos de pago quedan NULL 
  ----------------------------------------------------------------
  FOR i IN 1 .. :b_cant_postergar LOOP
    v_nuevo_nro_cuota  := v_ult_nro_cuota + i;
    v_nueva_fecha_venc := ADD_MONTHS(v_ult_fecha_venc, i);
    v_nuevo_valor      := ROUND(v_ult_valor_cuota * (1 + v_tasa_post));

    INSERT INTO cuota_credito_cliente
      (nro_solic_credito, nro_cuota, fecha_venc_cuota, valor_cuota,
       fecha_pago_cuota, monto_pagado, saldo_por_pagar, cod_forma_pago)
    VALUES
      (:b_nro_solic_credito, v_nuevo_nro_cuota, v_nueva_fecha_venc, v_nuevo_valor,
       NULL, NULL, NULL, NULL);
  END LOOP;

  COMMIT;
END;
/
---------------------------------------------------------------
-- 2 KAREN PRADENAS: cliente 67, solicitud 3004, postergar 1
---------------------------------------------------------------
BEGIN
  :b_nro_cliente       := 67;
  :b_nro_solic_credito := 3004;
  :b_cant_postergar    := 1;
END;
/
DECLARE
  v_ini_ano_ant DATE := TRUNC(ADD_MONTHS(SYSDATE, -12), 'YYYY');
  v_ini_ano_act DATE := TRUNC(SYSDATE, 'YYYY');
  v_fin_ano_ant DATE := v_ini_ano_act - 1;

  v_nombre_credito  CREDITO.NOMBRE_CREDITO%TYPE;

  v_ult_nro_cuota   CUOTA_CREDITO_CLIENTE.NRO_CUOTA%TYPE;
  v_ult_fecha_venc  CUOTA_CREDITO_CLIENTE.FECHA_VENC_CUOTA%TYPE;
  v_ult_valor_cuota CUOTA_CREDITO_CLIENTE.VALOR_CUOTA%TYPE;

  v_tasa_post NUMBER := 0;
  v_cant_creditos_ano_ant NUMBER := 0;

  v_nuevo_nro_cuota  NUMBER;
  v_nueva_fecha_venc DATE;
  v_nuevo_valor      NUMBER;
BEGIN
  SELECT cr.nombre_credito
  INTO   v_nombre_credito
  FROM   credito_cliente cc
  JOIN   credito cr ON cr.cod_credito = cc.cod_credito
  WHERE  cc.nro_solic_credito = :b_nro_solic_credito
  AND    cc.nro_cliente       = :b_nro_cliente;

  SELECT MAX(nro_cuota)
  INTO   v_ult_nro_cuota
  FROM   cuota_credito_cliente
  WHERE  nro_solic_credito = :b_nro_solic_credito;

  SELECT fecha_venc_cuota, valor_cuota
  INTO   v_ult_fecha_venc, v_ult_valor_cuota
  FROM   cuota_credito_cliente
  WHERE  nro_solic_credito = :b_nro_solic_credito
  AND    nro_cuota         = v_ult_nro_cuota;

  IF UPPER(v_nombre_credito) LIKE UPPER('%Hipotec%') THEN
    IF :b_cant_postergar = 1 THEN
      v_tasa_post := 0;
    ELSE
      v_tasa_post := 0.005;
    END IF;
  ELSIF UPPER(v_nombre_credito) LIKE UPPER('%Consumo%') THEN
    v_tasa_post := 0.01;
  ELSIF UPPER(v_nombre_credito) LIKE UPPER('%Automo%') THEN
    v_tasa_post := 0.02;
  ELSE
    v_tasa_post := 0;
  END IF;

  SELECT COUNT(*)
  INTO   v_cant_creditos_ano_ant
  FROM   credito_cliente cc
  WHERE  cc.nro_cliente = :b_nro_cliente
  AND    cc.fecha_otorga_cred >= v_ini_ano_ant
  AND    cc.fecha_otorga_cred <= v_fin_ano_ant;

  IF v_cant_creditos_ano_ant > 1 THEN
    UPDATE cuota_credito_cliente
    SET    fecha_pago_cuota = fecha_venc_cuota,
           monto_pagado     = valor_cuota,
           saldo_por_pagar  = 0
    WHERE  nro_solic_credito = :b_nro_solic_credito
    AND    nro_cuota         = v_ult_nro_cuota;
  END IF;

  FOR i IN 1 .. :b_cant_postergar LOOP
    v_nuevo_nro_cuota  := v_ult_nro_cuota + i;
    v_nueva_fecha_venc := ADD_MONTHS(v_ult_fecha_venc, i);
    v_nuevo_valor      := ROUND(v_ult_valor_cuota * (1 + v_tasa_post));

    INSERT INTO cuota_credito_cliente
      (nro_solic_credito, nro_cuota, fecha_venc_cuota, valor_cuota,
       fecha_pago_cuota, monto_pagado, saldo_por_pagar, cod_forma_pago)
    VALUES
      (:b_nro_solic_credito, v_nuevo_nro_cuota, v_nueva_fecha_venc, v_nuevo_valor,
       NULL, NULL, NULL, NULL);
  END LOOP;

  COMMIT;

END;
/

---------------------------------------------------------------
-- 3 JULIAN ARRIAGADA: cliente 13, solicitud 2004, postergar 1
---------------------------------------------------------------
BEGIN
  :b_nro_cliente       := 13;
  :b_nro_solic_credito := 2004;
  :b_cant_postergar    := 1;
END;
/
DECLARE
  v_ini_ano_ant DATE := TRUNC(ADD_MONTHS(SYSDATE, -12), 'YYYY');
  v_ini_ano_act DATE := TRUNC(SYSDATE, 'YYYY');
  v_fin_ano_ant DATE := v_ini_ano_act - 1;

  v_nombre_credito  CREDITO.NOMBRE_CREDITO%TYPE;

  v_ult_nro_cuota   CUOTA_CREDITO_CLIENTE.NRO_CUOTA%TYPE;
  v_ult_fecha_venc  CUOTA_CREDITO_CLIENTE.FECHA_VENC_CUOTA%TYPE;
  v_ult_valor_cuota CUOTA_CREDITO_CLIENTE.VALOR_CUOTA%TYPE;

  v_tasa_post NUMBER := 0;
  v_cant_creditos_ano_ant NUMBER := 0;

  v_nuevo_nro_cuota  NUMBER;
  v_nueva_fecha_venc DATE;
  v_nuevo_valor      NUMBER;
BEGIN
  SELECT cr.nombre_credito
  INTO   v_nombre_credito
  FROM   credito_cliente cc
  JOIN   credito cr ON cr.cod_credito = cc.cod_credito
  WHERE  cc.nro_solic_credito = :b_nro_solic_credito
  AND    cc.nro_cliente       = :b_nro_cliente;

  SELECT MAX(nro_cuota)
  INTO   v_ult_nro_cuota
  FROM   cuota_credito_cliente
  WHERE  nro_solic_credito = :b_nro_solic_credito;

  SELECT fecha_venc_cuota, valor_cuota
  INTO   v_ult_fecha_venc, v_ult_valor_cuota
  FROM   cuota_credito_cliente
  WHERE  nro_solic_credito = :b_nro_solic_credito
  AND    nro_cuota         = v_ult_nro_cuota;

  IF UPPER(v_nombre_credito) LIKE UPPER('%Hipotec%') THEN
    IF :b_cant_postergar = 1 THEN
      v_tasa_post := 0;
    ELSE
      v_tasa_post := 0.005;
    END IF;
  ELSIF UPPER(v_nombre_credito) LIKE UPPER('%Consumo%') THEN
    v_tasa_post := 0.01;
  ELSIF UPPER(v_nombre_credito) LIKE UPPER('%Automo%') THEN
    v_tasa_post := 0.02;
  ELSE
    v_tasa_post := 0;
  END IF;

  SELECT COUNT(*)
  INTO   v_cant_creditos_ano_ant
  FROM   credito_cliente cc
  WHERE  cc.nro_cliente = :b_nro_cliente
  AND    cc.fecha_otorga_cred >= v_ini_ano_ant
  AND    cc.fecha_otorga_cred <= v_fin_ano_ant;

  IF v_cant_creditos_ano_ant > 1 THEN
    UPDATE cuota_credito_cliente
    SET    fecha_pago_cuota = fecha_venc_cuota,
           monto_pagado     = valor_cuota,
           saldo_por_pagar  = 0
    WHERE  nro_solic_credito = :b_nro_solic_credito
    AND    nro_cuota         = v_ult_nro_cuota;
  END IF;

  FOR i IN 1 .. :b_cant_postergar LOOP
    v_nuevo_nro_cuota  := v_ult_nro_cuota + i;
    v_nueva_fecha_venc := ADD_MONTHS(v_ult_fecha_venc, i);
    v_nuevo_valor      := ROUND(v_ult_valor_cuota * (1 + v_tasa_post));

    INSERT INTO cuota_credito_cliente
      (nro_solic_credito, nro_cuota, fecha_venc_cuota, valor_cuota,
       fecha_pago_cuota, monto_pagado, saldo_por_pagar, cod_forma_pago)
    VALUES
      (:b_nro_solic_credito, v_nuevo_nro_cuota, v_nueva_fecha_venc, v_nuevo_valor,
       NULL, NULL, NULL, NULL);
  END LOOP;

  COMMIT;

END;
/


-- Evidencia del caso 2 en tabla
SELECT nro_solic_credito, nro_cuota, fecha_venc_cuota, valor_cuota,
       fecha_pago_cuota, monto_pagado, saldo_por_pagar, cod_forma_pago
FROM cuota_credito_cliente
WHERE nro_solic_credito IN (2001, 2004, 3004)
ORDER BY nro_solic_credito, nro_cuota;


