
-- PREPARACIÓN DEL AMBIENTE (CREACIÓN + POBLAMIENTO)
-- Ejecucion crea_pobla_tablas_bd_CLINICA_KETEKURA.sql para poblar base de datos.


SET SERVEROUTPUT ON;

-- CASO 1 - PAGO_MOROSO

-- 1) VARIABLE BIND (Año Acreditación)
-- Si acreditación es 2023, se informa 2022 (año anterior).

VARIABLE b_anno_acreditacion NUMBER;
EXEC :b_anno_acreditacion := EXTRACT(YEAR FROM SYSDATE);  -- Ejemplo año actual

-- 2) BLOQUE PL/SQL CASO 1

DECLARE
 
-- A. Año a informar (paramétrico)

    v_anno_informe NUMBER := :b_anno_acreditacion - 1;


    -- B. VARRAY multas por día segun Tabla 1

    TYPE t_multas IS VARRAY(7) OF NUMBER;
    v_arr_multas t_multas := t_multas(1200,1300,1700,1900,1100,2000,2300);

    /* ------------------------------------------------------------
       C. Cursor explícito: pagos fuera de plazo del año a informar
       - Se usa FECHA_PAGO para filtrar el año del pago.
       - Orden requerido:
         fecha_venc_pago ASC, apellido paterno ASC
       ------------------------------------------------------------ */
    CURSOR c_morosos(p_anno NUMBER) IS
        SELECT
            p.pac_run,
            p.dv_run,
            p.pnombre || ' ' || p.snombre || ' ' || p.apaterno || ' ' || p.amaterno AS pac_nombre,
            a.ate_id,
            pa.fecha_venc_pago,
            pa.fecha_pago,
            TRUNC(pa.fecha_pago - pa.fecha_venc_pago) AS dias_morosidad,
            e.nombre AS especialidad_atencion,
            p.fecha_nacimiento
        FROM pago_atencion pa
        JOIN atencion a     ON a.ate_id  = pa.ate_id
        JOIN paciente p     ON p.pac_run = a.pac_run
        JOIN especialidad e ON e.esp_id  = a.esp_id
        WHERE pa.fecha_pago IS NOT NULL
          AND pa.fecha_pago > pa.fecha_venc_pago
          AND EXTRACT(YEAR FROM pa.fecha_pago) = p_anno
        ORDER BY pa.fecha_venc_pago ASC, p.apaterno ASC;

-- D. Registro %ROWTYPE (estructura idéntica al cursor)

    v_reg c_morosos%ROWTYPE;

-- Variables auxiliares 
    v_edad        NUMBER := 0;
    v_pct_descto  NUMBER := 0;
    v_multa_dia   NUMBER := 0;
    v_monto_multa NUMBER := 0;

BEGIN

    -- 1) Limpieza de tabla destino para re-ejecución

    EXECUTE IMMEDIATE 'TRUNCATE TABLE PAGO_MOROSO';


    -- 2) Recorrer cursor y procesar fila a fila

    OPEN c_morosos(v_anno_informe);
    LOOP
        FETCH c_morosos INTO v_reg;
        EXIT WHEN c_morosos%NOTFOUND;

        -- 3) Cálculo de edad (usamos fecha_pago, no SYSDATE)

        v_edad := TRUNC(MONTHS_BETWEEN(v_reg.fecha_pago, v_reg.fecha_nacimiento) / 12);

        
        -- 4) Determinar multa diaria según especialidad (IF/ELSIF)
        
        IF UPPER(v_reg.especialidad_atencion) IN (UPPER('Cirugía General'), UPPER('Dermatología')) THEN
            v_multa_dia := v_arr_multas(1);

        ELSIF UPPER(v_reg.especialidad_atencion) = UPPER('Ortopedia y Traumatología') THEN
            v_multa_dia := v_arr_multas(2);

        ELSIF UPPER(v_reg.especialidad_atencion) IN (UPPER('Inmunología'), UPPER('Otorrinolaringología')) THEN
            v_multa_dia := v_arr_multas(3);

        ELSIF UPPER(v_reg.especialidad_atencion) IN (UPPER('Fisiatría'), UPPER('Medicina Interna')) THEN
            v_multa_dia := v_arr_multas(4);

        ELSIF UPPER(v_reg.especialidad_atencion) = UPPER('Medicina General') THEN
            v_multa_dia := v_arr_multas(5);

        ELSIF UPPER(v_reg.especialidad_atencion) = UPPER('Psiquiatría Adultos') THEN
            v_multa_dia := v_arr_multas(6);

        ELSIF UPPER(v_reg.especialidad_atencion) IN (UPPER('Cirugía Digestiva'), UPPER('Reumatología')) THEN
            v_multa_dia := v_arr_multas(7);


        ELSE
            v_multa_dia := 0; -- por seguridad
        END IF;

           -- 5) % descuento 3ra edad (si no hay tramo => 0)

        BEGIN
            SELECT porcentaje_descto
            INTO v_pct_descto
            FROM porc_descto_3ra_edad
            WHERE v_edad BETWEEN anno_ini AND anno_ter;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_pct_descto := 0;
        END;

           -- 6) Cálculo multa total:
              dias * multa_dia * (1 - %/100)
 
        v_monto_multa :=
            ROUND(v_reg.dias_morosidad * v_multa_dia * (1 - (v_pct_descto / 100)));

           -- 7) Insert a PAGO_MOROSO (formato tabla destino)

        INSERT INTO pago_moroso
        (pac_run, pac_dv_run, pac_nombre,
         ate_id, fecha_venc_pago, fecha_pago,
         dias_morosidad, especialidad_atencion, monto_multa)
        VALUES
        (v_reg.pac_run, v_reg.dv_run, v_reg.pac_nombre,
         v_reg.ate_id, v_reg.fecha_venc_pago, v_reg.fecha_pago,
         v_reg.dias_morosidad, v_reg.especialidad_atencion, v_monto_multa);

    END LOOP;
    CLOSE c_morosos;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('CASO 1 OK -> PAGO_MOROSO generado para año: ' || v_anno_informe);
END;
/

-- VERIFICACION

SELECT * FROM pago_moroso
ORDER BY fecha_venc_pago ASC, pac_nombre ASC;

-- CASO 2 - MEDICO_SERVICIO_COMUNIDAD
-- NOTA: antes de cada ejecución se elimina y recrea la tabla.

DROP TABLE medico_servicio_comunidad CASCADE CONSTRAINTS;

CREATE TABLE medico_servicio_comunidad
(
 id_med_scomun NUMBER GENERATED ALWAYS AS IDENTITY
   CONSTRAINT pk_med_serv_comunidad PRIMARY KEY,
 unidad               VARCHAR2(50) NOT NULL,
 run_medico           VARCHAR2(15) NOT NULL,
 nombre_medico        VARCHAR2(50) NOT NULL,
 correo_institucional VARCHAR2(25) NOT NULL,
 total_aten_medicas   NUMBER(5) NOT NULL,
 destinacion          VARCHAR2(50) NOT NULL
);

----------------------------------------------------------------
-- BLOQUE PL/SQL CASO 2
----------------------------------------------------------------
DECLARE
    -- A. Año anterior automático (sin fechas fijas)
    v_anno NUMBER := EXTRACT(YEAR FROM SYSDATE) - 1;

    /* ------------------------------------------------------------
       B. VARRAY Destinaciones
       1: SAPU
       2: Hospitales área Salud Pública
       3: CESFAM
       ------------------------------------------------------------ */
    TYPE t_dest IS VARRAY(3) OF VARCHAR2(60);
    v_arr_dest t_dest := t_dest(
        'Servicio de Atención Primaria de Urgencia (SAPU)',
        'Hospitales del área de la Salud Pública',
        'Centros de Salud Familiar (CESFAM)'
    );

    -- C. Máximo de atenciones del año anterior
    v_max_aten NUMBER := 0;

    /* ------------------------------------------------------------
       D. Cursor explícito: TODOS los médicos
       ------------------------------------------------------------ */
    CURSOR c_medicos(p_anno NUMBER) IS
        SELECT
            u.nombre AS unidad,
            m.med_run,
            m.dv_run,
            m.pnombre || ' ' || m.snombre || ' ' || 
            m.apaterno || ' ' || m.amaterno AS nombre_medico,
            m.apaterno AS apaterno,
            m.telefono AS telefono,
            NVL(x.total_aten, 0) AS total_aten_medicas
        FROM medico m
        JOIN unidad u ON u.uni_id = m.uni_id
        LEFT JOIN (
            SELECT med_run, COUNT(*) total_aten
            FROM atencion
            WHERE EXTRACT(YEAR FROM fecha_atencion) = p_anno
            GROUP BY med_run
        ) x ON x.med_run = m.med_run
        ORDER BY u.nombre ASC, m.apaterno ASC;

    -- E. Registro %ROWTYPE
    v_reg c_medicos%ROWTYPE;

    -- Variables auxiliares
    v_destino VARCHAR2(60);
    v_correo  VARCHAR2(25);

BEGIN
    -- 1) Obtener el máximo de atenciones del año anterior
    SELECT NVL(MAX(cnt), 0)
      INTO v_max_aten
      FROM (
        SELECT med_run, COUNT(*) cnt
        FROM atencion
        WHERE EXTRACT(YEAR FROM fecha_atencion) = v_anno
        GROUP BY med_run
      );

    -- 2) Recorrer TODOS los médicos
    OPEN c_medicos(v_anno);
    LOOP
        FETCH c_medicos INTO v_reg;
        EXIT WHEN c_medicos%NOTFOUND;

        -- 3) Filtrar: SOLO médicos con menos del máximo
        IF v_reg.total_aten_medicas < v_max_aten THEN

            -- 4) Determinar destinación según reglas del enunciado
            IF UPPER(v_reg.unidad) IN (UPPER('Atención Adulto'),
                                       UPPER('Atención Ambulatoria')) THEN
                v_destino := v_arr_dest(1);

            ELSIF UPPER(v_reg.unidad) = UPPER('Atención Urgencia') THEN
                IF v_reg.total_aten_medicas BETWEEN 0 AND 3 THEN
                    v_destino := v_arr_dest(1);
                ELSE
                    v_destino := v_arr_dest(2);
                END IF;

            ELSIF UPPER(v_reg.unidad) IN (UPPER('Cardiología'),
                                          UPPER('Oncológica'),
                                          UPPER('Paciente Crítico')) THEN
                v_destino := v_arr_dest(2);

            ELSIF UPPER(v_reg.unidad) IN (UPPER('Cirugía'),
                                          UPPER('Cirugía Plástica')) THEN
                IF v_reg.total_aten_medicas BETWEEN 0 AND 3 THEN
                    v_destino := v_arr_dest(1);
                ELSE
                    v_destino := v_arr_dest(2);
                END IF;

            ELSIF UPPER(v_reg.unidad) = UPPER('Psiquiatría y Salud Mental') THEN
                v_destino := v_arr_dest(3);

            ELSIF UPPER(v_reg.unidad) = UPPER('Traumatología Adulto') THEN
                IF v_reg.total_aten_medicas BETWEEN 0 AND 3 THEN
                    v_destino := v_arr_dest(1);
                ELSE
                    v_destino := v_arr_dest(2);
                END IF;

            ELSE
                v_destino := v_arr_dest(2); -- fallback seguro
            END IF;

            -- 5) Construcción del correo institucional
            v_correo :=
                UPPER(SUBSTR(v_reg.unidad, 1, 2)) ||
                LOWER(SUBSTR(v_reg.apaterno,
                             LENGTH(v_reg.apaterno) - 2, 2)) ||
                SUBSTR(NVL(TO_CHAR(v_reg.telefono), '0000000'), -7) ||
                '@medicocktk.cl';

            -- 6) INSERT en tabla destino
            INSERT INTO medico_servicio_comunidad
            (unidad, run_medico, nombre_medico,
             correo_institucional, total_aten_medicas, destinacion)
            VALUES
            (v_reg.unidad,
             TO_CHAR(v_reg.med_run) || '-' || v_reg.dv_run,
             v_reg.nombre_medico,
             v_correo,
             v_reg.total_aten_medicas,
             v_destino);

        END IF;

    END LOOP;
    CLOSE c_medicos;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE(
      'CASO 2 OK -> Año: ' || v_anno ||
      ' | Máx atenciones: ' || v_max_aten
    );
END;
/

-- VERIFICACION

SELECT unidad, run_medico, nombre_medico,
       correo_institucional, total_aten_medicas, destinacion
FROM medico_servicio_comunidad
ORDER BY unidad ASC, nombre_medico ASC;
