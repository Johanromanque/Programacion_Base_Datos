/* ============================================================
   SUMATIVA 3— PL/SQL
   HOTEL :LA ÚLTIMA OPORTUNIDAD

   - CASO 1: dejar automático el total de consumos del huésped.
             O sea, si alguien agrega / cambia / borra un consumo,
             el total en TOTAL_CONSUMOS se ajusta solo.
   - CASO 2: calcular cuánto debe pagar cada huésped cuando sale,
             y guardar el resultado en DETALLE_DIARIO_HUESPEDES (en pesos).
   ============================================================ */

SET SERVEROUTPUT ON;  -- Para ver mensajes con DBMS_OUTPUT.PUT_LINE

-------------------------------------------------------------------------------
-- CASO 1: TRIGGER
-- Este trigger se dispara solo cuando pasa algo en la tabla CONSUMO.
-- (insert / update / delete)
-- La idea es mantener TOTAL_CONSUMOS “al día” sin hacerlo a mano.
--
-- :NEW = valores nuevos (cuando insertas o actualizas)
-- :OLD = valores anteriores (cuando borras o actualizas)
-------------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_aiud_consumo_total
AFTER INSERT OR UPDATE OR DELETE ON consumo
FOR EACH ROW
DECLARE
    v_delta NUMBER; -- en UPDATE guardo la diferencia entre monto nuevo y monto antiguo
BEGIN
    IF INSERTING THEN
        -----------------------------------------------------------------------
        -- Si INSERTAN un consumo:
        -- sumo ese monto al total del huésped en TOTAL_CONSUMOS.
        -----------------------------------------------------------------------
        UPDATE total_consumos
           SET monto_consumos = NVL(monto_consumos, 0) + NVL(:NEW.monto, 0)
         WHERE id_huesped = :NEW.id_huesped;

        -----------------------------------------------------------------------
        -- Si no existía fila del huésped en TOTAL_CONSUMOS,
        -- el UPDATE no actualiza nada, entonces creo la fila.
        -----------------------------------------------------------------------
        IF SQL%ROWCOUNT = 0 THEN
            INSERT INTO total_consumos (id_huesped, monto_consumos)
            VALUES (:NEW.id_huesped, NVL(:NEW.monto, 0));
        END IF;

    ELSIF UPDATING THEN
        -----------------------------------------------------------------------
        -- Si ACTUALIZAN el monto de un consumo:
        -- no debo sumar todo de nuevo, solo ajustar la diferencia.
        -- delta = nuevo - antiguo
        -----------------------------------------------------------------------
        v_delta := NVL(:NEW.monto, 0) - NVL(:OLD.monto, 0);

        UPDATE total_consumos
           SET monto_consumos = NVL(monto_consumos, 0) + v_delta
         WHERE id_huesped = :NEW.id_huesped;

        -- Por si no existía el huésped en TOTAL_CONSUMOS, lo creo igual.
        IF SQL%ROWCOUNT = 0 THEN
            INSERT INTO total_consumos (id_huesped, monto_consumos)
            VALUES (:NEW.id_huesped, NVL(:NEW.monto, 0));
        END IF;

    ELSIF DELETING THEN
        -----------------------------------------------------------------------
        -- Si BORRAN un consumo:
        -- resto el monto que se eliminó al total del huésped.
        -- (aquí uso :OLD porque esa fila ya no existirá)
        -----------------------------------------------------------------------
        UPDATE total_consumos
           SET monto_consumos = NVL(monto_consumos, 0) - NVL(:OLD.monto, 0)
         WHERE id_huesped = :OLD.id_huesped;
    END IF;
END;
/
-------------------------------------------------------------------------------
-- CASO 1: BLOQUE DE PRUEBA
-- Esto es solo para probar que el trigger funciona con lo que pide el enunciado:
-- 1) insertar un consumo nuevo (id siguiente al máximo)
-- 2) eliminar el consumo 11473
-- 3) actualizar el consumo 10688 a 95
-------------------------------------------------------------------------------
DECLARE
    v_next_id consumo.id_consumo%TYPE; -- uso el mismo tipo de dato de la columna
BEGIN
    -- saco el último id_consumo y le sumo 1 (para tener el siguiente)
    SELECT NVL(MAX(id_consumo), 0) + 1
      INTO v_next_id
      FROM consumo;

    -- 1) INSERT 
    INSERT INTO consumo (id_consumo, id_reserva, id_huesped, monto)
    VALUES (v_next_id, 1587, 340006, 150);

    -- 2) DELETE 
    DELETE FROM consumo
     WHERE id_consumo = 11473;

    -- 3) UPDATE 
    UPDATE consumo
       SET monto = 95
     WHERE id_consumo = 10688;

    COMMIT; -- confirmo los cambios
    DBMS_OUTPUT.PUT_LINE('CASO 1 OK. Nuevo ID insertado: ' || v_next_id);
END;
/
-------------------------------------------------------------------------------
-- CASO 2: PACKAGE (TOURS)
-- Aquí guardo lo relacionado a tours en un package, porque lo piden así.
-- La función devuelve el total en USD de tours de un huésped.
-- Si no tiene tours, debe devolver 0.
-------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE pkg_tours IS
    FUNCTION fn_monto_tours_usd (p_id_huesped NUMBER) RETURN NUMBER;
END pkg_tours;
/

CREATE OR REPLACE PACKAGE BODY pkg_tours IS
    FUNCTION fn_monto_tours_usd (p_id_huesped NUMBER) RETURN NUMBER IS
        v_total NUMBER;
    BEGIN
        -- Sumo tours: valor_tour * num_personas (si num_personas viene NULL, uso 1)
        -- SUM puede devolver NULL si no hay filas, por eso NVL(...,0)
        SELECT NVL(SUM(t.valor_tour * NVL(ht.num_personas, 1)), 0)
          INTO v_total
          FROM huesped_tour ht
          JOIN tour t ON t.id_tour = ht.id_tour
         WHERE ht.id_huesped = p_id_huesped;

        RETURN v_total;

    EXCEPTION
        -- Si algo falla, no quiero que el proceso se caiga: devuelvo 0.
        WHEN OTHERS THEN
            RETURN 0;
    END fn_monto_tours_usd;
END pkg_tours;
/
-------------------------------------------------------------------------------
-- CASO 2: FUNCIÓN FN_AGENCIA
-- Devuelve el nombre de la agencia del huésped.
-- Si ocurre un error, lo guardo en REG_ERRORES (con SQ_ERROR)
-- y devuelvo el texto: "NO REGISTRA AGENCIA" (tal cual lo pide).
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_agencia (p_id_huesped NUMBER)
RETURN VARCHAR2
IS
    v_agencia agencia.nom_agencia%TYPE;
    v_err     VARCHAR2(300);
BEGIN
    -- Busco la agencia del huésped
    SELECT a.nom_agencia
      INTO v_agencia
      FROM huesped h
      JOIN agencia a ON a.id_agencia = h.id_agencia
     WHERE h.id_huesped = p_id_huesped;

    RETURN v_agencia;

EXCEPTION
    WHEN OTHERS THEN
        v_err := SUBSTR(SQLERRM, 1, 300);

        -- Registro el error para revisarlo después
        INSERT INTO reg_errores (id_error, nomsubprograma, msg_error)
        VALUES (
            sq_error.NEXTVAL,
            'FN_AGENCIA: id_huesped=' || TO_CHAR(p_id_huesped),
            v_err
        );

        RETURN 'NO REGISTRA AGENCIA';
END;
/
-------------------------------------------------------------------------------
-- CASO 2: FUNCIÓN FN_CONSUMOS_USD
-- Devuelve los consumos del huésped (en USD) consultando TOTAL_CONSUMOS.
-- Si no hay registro (NO_DATA_FOUND), debe devolver 0.
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_consumos_usd (p_id_huesped NUMBER)
RETURN NUMBER
IS
    v_monto NUMBER;
    v_err   VARCHAR2(300);
BEGIN
    SELECT tc.monto_consumos
      INTO v_monto
      FROM total_consumos tc
     WHERE tc.id_huesped = p_id_huesped;

    RETURN NVL(v_monto, 0);

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        -- No hay consumos registrados
        RETURN 0;

    WHEN OTHERS THEN
        -- Error raro: lo registro y devuelvo 0 para que el proceso siga.
        v_err := SUBSTR(SQLERRM, 1, 300);

        INSERT INTO reg_errores (id_error, nomsubprograma, msg_error)
        VALUES (
            sq_error.NEXTVAL,
            'FN_CONSUMOS_USD: id_huesped=' || TO_CHAR(p_id_huesped),
            v_err
        );

        RETURN 0;
END;
/
-------------------------------------------------------------------------------
-- SUBPROGRAMA EXTRA 
-- FN_PCT_DESC_CONSUMOS:
-- Busca el porcentaje de descuento según los tramos de consumos.
-- Si no cae en ningún tramo, devuelve 0.

-- esto asume que pct viene como 0.10 (no como 10).
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_pct_desc_consumos (p_consumos_usd NUMBER)
RETURN NUMBER
IS
    v_pct tramos_consumos.pct%TYPE;
BEGIN
    SELECT tc.pct
      INTO v_pct
      FROM tramos_consumos tc
     WHERE p_consumos_usd BETWEEN tc.vmin_tramo AND tc.vmax_tramo;

    RETURN NVL(v_pct, 0);

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 0;
    WHEN OTHERS THEN
        RETURN 0;
END fn_pct_desc_consumos;
/
-------------------------------------------------------------------------------
-- CASO 2: PROCEDIMIENTO PRINCIPAL
-- Procesa todos los huéspedes que salen en p_fecha_proceso.
-- Recibe p_tc_dolar para convertir a pesos (CLP) al final.
--
-- Lo importante:
-- 1) calcular en USD
-- 2) redondear
-- 3) guardar en CLP en DETALLE_DIARIO_HUESPEDES
-- 4) limpiar tablas antes de correr (para poder ejecutar varias veces)
-------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_generar_detalle_diario (
    p_fecha_proceso IN DATE,
    p_tc_dolar      IN NUMBER
) IS
    -- Cursor: lista las reservas cuya salida cae justo en el día del proceso
    CURSOR c_salidas IS
        SELECT r.id_reserva,
               r.id_huesped,
               r.ingreso,
               r.estadia
          FROM reserva r
         WHERE TRUNC(r.ingreso + r.estadia) = TRUNC(p_fecha_proceso);

    v_nombre  VARCHAR2(60);
    v_agencia VARCHAR2(40);

    -- Variables de cálculo (USD)
    v_aloj_usd         NUMBER;
    v_cons_usd         NUMBER;
    v_tours_usd        NUMBER;
    v_personas         NUMBER;
    v_val_personas_usd NUMBER;
    v_subtotal_usd     NUMBER;
    v_pct_cons         NUMBER;
    v_desc_cons_usd    NUMBER;
    v_desc_ag_usd      NUMBER;
    v_total_usd        NUMBER;

    v_pct_agencia      NUMBER := 0.12; -- 12% para “Viajes Alberti”

    -- mini-procedimiento para guardar errores sin repetir código
    PROCEDURE log_error (p_sub VARCHAR2, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO reg_errores (id_error, nomsubprograma, msg_error)
        VALUES (
            sq_error.NEXTVAL,
            SUBSTR(p_sub, 1, 200),
            SUBSTR(p_msg, 1, 300)
        );
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END log_error;

BEGIN
    -- Limpio resultados y errores para poder ejecutar el proceso varias veces
    DELETE FROM detalle_diario_huespedes;
    DELETE FROM reg_errores;
    COMMIT;

    -- Recorro cada reserva que sale ese día
    FOR rec IN c_salidas LOOP
        BEGIN
            -- 1) Nombre del huésped (si falla, lo dejo con texto y registro el error)
            BEGIN
                SELECT (h.appat_huesped || ' ' || h.apmat_huesped || ' ' || h.nom_huesped)
                  INTO v_nombre
                  FROM huesped h
                 WHERE h.id_huesped = rec.id_huesped;
            EXCEPTION
                WHEN OTHERS THEN
                    v_nombre := 'NO REGISTRA NOMBRE';
                    log_error('SP: NOMBRE id_huesped=' || rec.id_huesped, SQLERRM);
            END;

            -- 2) Agencia (usa la función que pide el enunciado)
            v_agencia := fn_agencia(rec.id_huesped);

            -- 3) Alojamiento en USD: (habitación + minibar) * días de estadía
            BEGIN
                SELECT NVL(SUM((ha.valor_habitacion + ha.valor_minibar) * rec.estadia), 0)
                  INTO v_aloj_usd
                  FROM detalle_reserva dr
                  JOIN habitacion ha ON ha.id_habitacion = dr.id_habitacion
                 WHERE dr.id_reserva = rec.id_reserva;
            EXCEPTION
                WHEN OTHERS THEN
                    v_aloj_usd := 0;
                    log_error('SP: ALOJ id_reserva=' || rec.id_reserva, SQLERRM);
            END;

            -- 4) Consumos en USD (consulta TOTAL_CONSUMOS mediante función)
            v_cons_usd := fn_consumos_usd(rec.id_huesped);

            -- 5) Tours en USD (package). Se guarda, pero no entra en subtotal/total.
            v_tours_usd := pkg_tours.fn_monto_tours_usd(rec.id_huesped);

            -- 6) Personas: según tipo habitación (S=1, D=2, T=3, C=4)
            BEGIN
                SELECT NVL(SUM(
                    CASE UPPER(TRIM(ha.tipo_habitacion))
                        WHEN 'S' THEN 1
                        WHEN 'D' THEN 2
                        WHEN 'T' THEN 3
                        WHEN 'C' THEN 4
                        ELSE 1
                    END
                ), 0)
                  INTO v_personas
                  FROM detalle_reserva dr
                  JOIN habitacion ha ON ha.id_habitacion = dr.id_habitacion
                 WHERE dr.id_reserva = rec.id_reserva;

                IF v_personas = 0 THEN
                    v_personas := 1;
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    v_personas := 1;
                    log_error('SP: PERSONAS id_reserva=' || rec.id_reserva, SQLERRM);
            END;

            -- 7) Cargo personas: 35.000 CLP por persona, lo convierto a USD
            v_val_personas_usd := ROUND((35000 * v_personas) / p_tc_dolar);

            -- 8) Subtotal USD (sin tours): alojamiento + consumos + valor_personas
            v_subtotal_usd := ROUND(v_aloj_usd + v_cons_usd + v_val_personas_usd);

            -- 9) Descuento por consumos (por tramos)
            v_pct_cons      := fn_pct_desc_consumos(v_cons_usd);
            v_desc_cons_usd := ROUND(v_cons_usd * v_pct_cons);

            -- 10) Descuento agencia: 12% del subtotal solo si es “VIAJES ALBERTI”
            IF UPPER(TRIM(v_agencia)) = 'VIAJES ALBERTI' THEN
                v_desc_ag_usd := ROUND(v_subtotal_usd * v_pct_agencia);
            ELSE
                v_desc_ag_usd := 0;
            END IF;

            -- 11) Total USD = subtotal - descuentos
            v_total_usd := ROUND(v_subtotal_usd - v_desc_cons_usd - v_desc_ag_usd);

            -- 12) Guardo en CLP (USD * tipo_cambio), todo redondeado
            INSERT INTO detalle_diario_huespedes (
                id_huesped, nombre, agencia,
                alojamiento, consumos, tours,
                subtotal_pago, descuento_consumos,
                descuentos_agencia, total
            ) VALUES (
                rec.id_huesped, v_nombre, v_agencia,
                ROUND(v_aloj_usd * p_tc_dolar),
                ROUND(v_cons_usd * p_tc_dolar),
                ROUND(v_tours_usd * p_tc_dolar),
                ROUND(v_subtotal_usd * p_tc_dolar),
                ROUND(v_desc_cons_usd * p_tc_dolar),
                ROUND(v_desc_ag_usd * p_tc_dolar),
                ROUND(v_total_usd * p_tc_dolar)
            );

        EXCEPTION
            -- Si algo falla en este huésped, lo registro y sigo con el siguiente
            WHEN OTHERS THEN
                log_error('SP: LOOP id_reserva=' || rec.id_reserva, SQLERRM);
        END;
    END LOOP;

    COMMIT;
END sp_generar_detalle_diario;
/
-------------------------------------------------------------------------------
-- EJECUCIÓN DE PRUEBA 
-- Fecha proceso: 18/08/2021
-- Tipo de cambio: 915
-------------------------------------------------------------------------------
BEGIN
    sp_generar_detalle_diario(
        p_fecha_proceso => DATE '2021-08-18',
        p_tc_dolar      => 915
    );
END;
/
-------------------------------------------------------------------------------
-- CONSULTAS PARA VER RESULTADOS (revisar)
-------------------------------------------------------------------------------
SELECT *
  FROM detalle_diario_huespedes
 ORDER BY id_huesped;

SELECT *
  FROM reg_errores
 ORDER BY id_error;
 