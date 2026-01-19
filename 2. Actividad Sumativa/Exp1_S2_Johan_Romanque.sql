---------------------------------------------------------------
-- TRUCK RENTAL - ACTIVIDAD SUMATIVA
---------------------------------------------------------------


-- BIND fecha de proceso 

VAR b_fecha_proceso DATE;

BEGIN
  :b_fecha_proceso := SYSDATE; -- Fecha actual del sistema
END;
/

DECLARE
-- VARIABLES DE CONTROL
  v_contador        NUMBER := 0;   -- Cuenta empleados procesados
  v_total_emp       NUMBER := 0;   -- Total empleados en BD

-- VARIABLES %TYPE 
  v_id_emp          empleado.id_emp%TYPE;
  v_numrun          empleado.numrun_emp%TYPE;
  v_dvrun           empleado.dvrun_emp%TYPE;
  v_nombre          empleado.nombre_empleado%TYPE;
  v_estado_civil    empleado.estado_civil%TYPE;
  v_sueldo          empleado.sueldo_base%TYPE;
  v_fecha_nac       empleado.fecha_nacimiento%TYPE;
  v_fecha_contrato  empleado.fecha_contrato%TYPE;

-- VARIABLES PARA CÁLCULOS
  v_nombre_usuario  VARCHAR2(20);
  v_clave_usuario   VARCHAR2(20);
  v_anios_trabajo   NUMBER;
  v_mes_anio_bd     VARCHAR2(6);

BEGIN
-- TRUNCADO DE TABLA 
  EXECUTE IMMEDIATE 'TRUNCATE TABLE USUARIO_CLAVE';

-- TOTAL DE EMPLEADOS PARA VALIDAR COMMIT
  SELECT COUNT(*)
  INTO   v_total_emp
  FROM   empleado;


-- iteracion for para procesar todos los empleados
  FOR r IN (
    SELECT *
    FROM empleado
    WHERE id_emp BETWEEN 100 AND 320
    ORDER BY id_emp
  ) LOOP

-- Asignación de datos del empleado
    v_id_emp         := r.id_emp;
    v_numrun         := r.numrun_emp;
    v_dvrun          := r.dvrun_emp;
    v_nombre         := r.nombre_empleado;
    v_estado_civil   := r.estado_civil;
    v_sueldo         := r.sueldo_base;
    v_fecha_nac      := r.fecha_nacimiento;
    v_fecha_contrato := r.fecha_contrato;

-- CÁLCULOS EN PL/SQL 

    -- Años trabajados
    v_anios_trabajo := TRUNC(MONTHS_BETWEEN(:b_fecha_proceso, v_fecha_contrato) / 12);

    -- Mes y año de la BD (MMYYYY)
    v_mes_anio_bd := TO_CHAR(:b_fecha_proceso, 'MMYYYY');


-- GENERACIÓN NOMBRE USUARIO

    v_nombre_usuario :=
         LOWER(SUBSTR(v_estado_civil,1,1)) ||
         LOWER(SUBSTR(v_nombre,1,3)) ||
         LENGTH(v_nombre) ||
         '*' ||
         MOD(v_sueldo,10) ||
         v_dvrun ||
         v_anios_trabajo;

    IF v_anios_trabajo < 10 THEN
      v_nombre_usuario := v_nombre_usuario || 'X';
    END IF;

-- GENERACIÓN CLAVE USUARIO
    v_clave_usuario :=
         SUBSTR(v_numrun,3,1) ||
         (EXTRACT(YEAR FROM v_fecha_nac) + 2) ||
         LPAD(MOD(TRUNC(v_sueldo/1)-1,1000),3,'0');

-- Letras de apellido segun estado civil
    IF v_estado_civil IN ('CASADO','ACUERDO') THEN
      v_clave_usuario := v_clave_usuario || LOWER(SUBSTR(r.appaterno,1,2));
    ELSIF v_estado_civil IN ('SOLTERO','DIVORCIADO') THEN
      v_clave_usuario := v_clave_usuario || LOWER(SUBSTR(r.appaterno,1,1) || SUBSTR(r.appaterno,-1,1));
    ELSIF v_estado_civil = 'VIUDO' THEN
      v_clave_usuario := v_clave_usuario || LOWER(SUBSTR(r.appaterno,-3,2));
    ELSE
      v_clave_usuario := v_clave_usuario || LOWER(SUBSTR(r.appaterno,-2,2));
    END IF;

    v_clave_usuario := v_clave_usuario || v_id_emp || v_mes_anio_bd;


 -- INSERT EN TABLA DESTINO
    INSERT INTO usuario_clave
    VALUES (
      v_id_emp,
      v_numrun,
      v_dvrun,
      v_nombre,
      v_nombre_usuario,
      v_clave_usuario
    );

    v_contador := v_contador + 1;

  END LOOP;

-- CONFIRMACIÓN DE TRANSACCIÓN
  IF v_contador = v_total_emp THEN
    COMMIT;
  ELSE
    ROLLBACK;
  END IF;

END;
/
