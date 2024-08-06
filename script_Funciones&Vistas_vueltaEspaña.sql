--CONSULTAS-------------------------------------------------------------------------------------------------------------------
------1------------------------------------------
SELECT  
    C.primerNombre, 
    C.segundoNombre, 
    C.primerApellido, 
    C.segundoApellido, 
    AVG(RP.cantidadPuntosObtenidos) AS promedioPuntos 
FROM Ciclistas C 
JOIN RegistroDePuntos RP ON C.idCiclista = RP.idCiclista 
GROUP BY C.primerNombre, C.segundoNombre, C.primerApellido, C.segundoApellido 
HAVING AVG(RP.cantidadPuntosObtenidos) > ( 
    SELECT AVG(cantidadPuntosObtenidos)  
    FROM RegistroDePuntos 
) 
ORDER BY promedioPuntos DESC; 

------2------------------------------------------
SELECT e.nombre, COUNT(ec.idEquipo) AS cantidad_ciclistas  
FROM Equipos e  
LEFT JOIN EquiposDeCiclistas ec ON e.idEquipo = ec.idEquipo  
GROUP BY e.idEquipo  
ORDER BY cantidad_ciclistas DESC; 

--FUNCIONES-------------------------------------------------------------------------------------------------------------------
------1------------------------------------------
CREATE OR REPLACE FUNCTION CiclistasSancionados(  
    NumeroDeLaEtapa INTEGER,  
    AñoDeLaEdicion INTEGER  
)  
RETURNS TABLE (  
    primerNombre VARCHAR(300),  
    segundoNombre VARCHAR(300),  
    primerApellido VARCHAR(300),  
    segundoApellido VARCHAR(300),  
    regla VARCHAR(100),  
    totalSanciones BIGINT  
)  
AS  
$$  
BEGIN  
    RETURN QUERY  
    SELECT   
        C.primerNombre,  
        C.segundoNombre,  
        C.primerApellido,  
        C.segundoApellido,  
        R.nombre AS regla,  
        COUNT(S.idSancion) AS totalSanciones  
    FROM Sanciones S  
    JOIN Ciclistas C ON S.idCiclista = C.idCiclista  
    JOIN Reglas R ON S.idRegla = R.idRegla  
    WHERE S.idEtapa = (  
        SELECT idEtapa   
        FROM Etapas   
        WHERE numeroEtapa = NumeroDeLaEtapa   
        AND idEdicion = (  
            SELECT idEdicion   
            FROM Ediciones   
            WHERE añoRealizacion = AñoDeLaEdicion  
        )  
    )  
    GROUP BY C.primerNombre, C.segundoNombre, C.primerApellido, C.segundoApellido, R.nombre;  
END;  
$$ LANGUAGE plpgsql; 

------2------------------------------------------
CREATE OR REPLACE FUNCTION CiclistasEnEdiciones( 
    AñosEdiciones DATE 
) 
RETURNS TABLE ( 
    primerNombre VARCHAR(300), 
    segundoNombre VARCHAR(300), 
    primerApellido VARCHAR(300), 
    segundoApellido VARCHAR(300), 
    cantidadEdiciones INTEGER 
) 
AS 
$$ 
BEGIN 
    RETURN QUERY 
    SELECT  
        C.primerNombre, 
        C.segundoNombre, 
        C.primerApellido, 
        C.segundoApellido, 
        COUNT(EC.idEdicion) AS cantidadEdiciones 
    FROM Ciclistas C 
    JOIN EdicionesDeCiclistas EC ON C.idCiclista = EC.idCiclista 
    WHERE EC.idEdicion IN ( 
        SELECT idEdicion  
        FROM Ediciones  
        WHERE añoRealizacion = ANY(AñosEdiciones) 
    ) 
    GROUP BY C.primerNombre, C.segundoNombre, C.primerApellido, C.segundoApellido 
    HAVING COUNT(EC.idEdicion) = (SELECT COUNT(*) FROM Ediciones WHERE añoRealizacion = ANY(AñosEdiciones)) 
    ORDER BY cantidadEdiciones DESC; 
END; 
$$ LANGUAGE plpgsql; 

-----3------------------------------------------
CREATE OR REPLACE FUNCTION obtener_mejor_tiempo(etapa_id INTEGER)  
RETURNS TABLE (nombre_ciclista VARCHAR, apellido_ciclista VARCHAR, mejor_tiempo TIME) AS $$  
BEGIN  
    RETURN QUERY  
    SELECT    
        c.primerNombre, c.primerApellido, (re.duracion - re.bonificacion + re.penalizacion) AS mejor_tiempo   
    FROM    
        Ciclistas c    
    INNER JOIN    
        registroetapas re ON re.idCiclista = c.idCiclista   
    WHERE    
        (re.duracion - re.bonificacion + re.penalizacion) = (  
            SELECT MIN(duracion - bonificacion + penalizacion) 
            FROM registroetapas 	 
            WHERE idetapa = etapa_id 
        ) 
    AND 
        re.idetapa = etapa_id;   
END;  
$$ LANGUAGE plpgsql; 
------4------------------------------------------
CREATE OR REPLACE FUNCTION obtener_ciclistas_max_puntos(año_edicion INTEGER)  
RETURNS TABLE ( 
    tipoPunto VARCHAR, 
    primerNombre VARCHAR, 
    segundoNombre VARCHAR, 
    primerApellido VARCHAR, 
    segundoApellido VARCHAR, 
    totalPuntos INTEGER 
) AS $$ 
BEGIN 
    RETURN QUERY 
    SELECT 
        TP.nombre AS tipoPunto, 
        C.primerNombre, 
        C.segundoNombre, 
        C.primerApellido, 
        C.segundoApellido, 
        SubConsulta.totalPuntos::INTEGER 
    FROM ( 
        SELECT 
            RP.idTipoPunto, 
            RP.idCiclista, 
            SUM(RP.cantidadPuntosObtenidos)::INTEGER AS totalPuntos, 
            ROW_NUMBER() OVER (PARTITION BY RP.idTipoPunto ORDER BY SUM(RP.cantidadPuntosObtenidos) DESC) AS podio 
        FROM RegistroDePuntos RP 
        JOIN Etapas E ON RP.idEtapa = E.idEtapa 
        WHERE E.idEdicion = (SELECT idEdicion FROM Ediciones WHERE añoRealizacion = año_edicion) 
        GROUP BY RP.idTipoPunto, RP.idCiclista 
    ) AS SubConsulta 
    JOIN Ciclistas C ON SubConsulta.idCiclista = C.idCiclista 
    JOIN TipoDePuntos TP ON SubConsulta.idTipoPunto = TP.idTipoPunto 
    WHERE SubConsulta.podio = 1; --Elige el que quedo en primera posicion en cada tipo de punto 
END; 
$$ LANGUAGE plpgsql; 

------5------------------------------------------
CREATE OR REPLACE FUNCTION PaisConMasGanadoresDeEtapas( 
    AñoEdicion INTEGER 
) 
RETURNS TABLE ( 
    nombrePais VARCHAR(100), 
    cantidadCiclistas INTEGER 
) 
AS 
$$ 
BEGIN 
    RETURN QUERY 
    SELECT  
        P.nombre AS nombrePais, 
        COUNT(DISTINCT C.idCiclista)::integer AS cantidadCiclistas 
    FROM Ciclistas C 
    JOIN Paises P ON C.idPaisNacimiento = P.idPais 
    JOIN RegistroEtapas RE ON C.idCiclista = RE.idCiclista 
    JOIN Etapas E ON RE.idEtapa = E.idEtapa 
    JOIN Ediciones ED ON E.idEdicion = ED.idEdicion 
    WHERE ED.añoRealizacion = AñoEdicion 
    AND RE.duracion = ( 
        SELECT MIN(RE2.duracion) 
        FROM RegistroEtapas RE2 
        WHERE RE2.idEtapa = E.idEtapa 
    ) 
    GROUP BY P.nombre 
    ORDER BY cantidadCiclistas DESC 
    LIMIT 1; 
END; 
$$ LANGUAGE plpgsql; 

------6------------------------------------------
CREATE OR REPLACE FUNCTION calcular_clasificacion_puntos_por_etapas( 
    id_etapa INT 
) RETURNS TABLE ( 
    ranking INT, 
    primerNombre VARCHAR(300), 
    primerApellido VARCHAR(300), 
    total_puntos INT, 
  	tiempo_total INTERVAL 
) 
AS $$ 
BEGIN 
    RETURN QUERY  
    SELECT 
        CAST(RANK() OVER (ORDER BY COALESCE(SUM(rp.cantidadpuntosobtenidos), 0) DESC, COALESCE(SUM( 
            EXTRACT(EPOCH FROM re.duracion)  
            - EXTRACT(EPOCH FROM re.bonificacion)  
            + EXTRACT(EPOCH FROM re.penalizacion) 
        ), 0) ASC) AS INT) AS ranking, 
        c.primerNombre, 
        c.primerApellido, 
        COALESCE(SUM(rp.cantidadpuntosobtenidos), 0)::INT AS total_puntos, 
        INTERVAL '1 second' * COALESCE(SUM( 
            EXTRACT(EPOCH FROM re.duracion)  
            - EXTRACT(EPOCH FROM re.bonificacion)  
            + EXTRACT(EPOCH FROM re.penalizacion) 
        ), 0) AS tiempo_total 
    FROM  
        Registrodepuntos rp 
    JOIN  
        Ciclistas c ON rp.idCiclista = c.idCiclista 
    LEFT JOIN  
        RegistroEtapas re ON re.idCiclista = rp.idCiclista AND re.idEtapa = rp.idEtapa 
    LEFT JOIN  
        Etapas e ON rp.idEtapa = e.idEtapa 
    WHERE  
        rp.idEtapa <= id_etapa 
        AND e.idEdicion = (SELECT idEdicion FROM Etapas WHERE idEtapa = id_etapa)  -- Solo para la misma edición que la etapa solicitada 
        AND rp.idtipopunto IN (10, 12) 
    GROUP BY  
        rp.idCiclista, c.primerNombre, c.primerApellido; 
END; 
$$ LANGUAGE plpgsql; 

------7------------------------------------------
CREATE OR REPLACE FUNCTION calcular_clasificacion_montana_por_etapas( 
    id_etapa INT 
) RETURNS TABLE ( 
    ranking INT, 
    primerNombre VARCHAR(300), 
    primerApellido VARCHAR(300), 
    total_puntos_montana INT 
) 
AS $$ 
BEGIN 
    RETURN QUERY  
    WITH MontañaPuntos AS ( 
        SELECT  
            rp.idCiclista, 
            COALESCE(SUM(CASE WHEN rp.idTipoPunto IN (13, 14, 15, 16) THEN rp.cantidadpuntosobtenidos ELSE 0 END), 0)::INT AS total_puntos_montana 
        FROM  
            Registrodepuntos rp 
        JOIN  
            Tipodepuntos tp ON rp.idTipoPunto = tp.idTipoPunto 
        JOIN  
            Etapas e ON rp.idEtapa = e.idEtapa 
        WHERE  
            rp.idEtapa <= id_etapa 
            AND e.idEdicion = (SELECT idEdicion FROM Etapas WHERE idEtapa = id_etapa)  -- Solo para la misma edición que la etapa solicitada 
        GROUP BY  
            rp.idCiclista 
    ) 
    SELECT  
        CAST(RANK() OVER (ORDER BY mp.total_puntos_montana DESC) AS INT) AS ranking, 
        c.primerNombre, 
        c.primerApellido, 
        mp.total_puntos_montana 
    FROM  
        MontañaPuntos mp 
    JOIN  
        Ciclistas c ON mp.idCiclista = c.idCiclista 
    ORDER BY  
        ranking; 
END; 
$$ LANGUAGE plpgsql; 

------8------------------------------------------
CREATE OR REPLACE FUNCTION calcular_clasificacion_jovenes_por_etapas( 
    id_etapa INT 
) RETURNS TABLE ( 
    ranking INT, 
    primerNombre VARCHAR(300), 
    primerApellido VARCHAR(300), 
    duracion INTERVAL 
) 
AS $$ 
BEGIN 
    RETURN QUERY 
    WITH CiclistasJovenes AS ( 
        SELECT  
            C.idCiclista, 
            C.primerNombre, 
            C.primerApellido, 
            ED.añoRealizacion, 
            C.fechaNacimiento 
        FROM Ciclistas C 
        JOIN RegistroEtapas RE ON C.idCiclista = RE.idCiclista 
        JOIN Etapas E ON RE.idEtapa = E.idEtapa 
        JOIN Ediciones ED ON E.idEdicion = ED.idEdicion 
        WHERE E.idEtapa = id_etapa 
          AND AGE(MAKE_DATE(ED.añoRealizacion, 1, 1), C.fechaNacimiento) < INTERVAL '25 years' 
    ), 
    DuracionTotal AS ( 
        SELECT  
            RE.idCiclista, 
            INTERVAL '1 second' * SUM( 
                EXTRACT(EPOCH FROM RE.duracion)  
                - COALESCE(EXTRACT(EPOCH FROM RE.bonificacion), 0)  
                + COALESCE(EXTRACT(EPOCH FROM RE.penalizacion), 0) 
            ) AS duracionTotal 
        FROM RegistroEtapas RE 
        JOIN Etapas E ON RE.idEtapa = E.idEtapa 
        JOIN CiclistasJovenes CJ ON RE.idCiclista = CJ.idCiclista 
        WHERE E.idEtapa <= id_etapa 
          AND E.idEdicion = (SELECT idEdicion FROM Etapas WHERE idEtapa = id_etapa) 
        GROUP BY RE.idCiclista 
    ) 
    SELECT  
        CAST(RANK() OVER (ORDER BY DT.duracionTotal ASC) AS INT) AS ranking, 
        CJ.primerNombre, 
        CJ.primerApellido, 
        DT.duracionTotal AS duracion 
    FROM CiclistasJovenes CJ 
    JOIN DuracionTotal DT ON CJ.idCiclista = DT.idCiclista 
    ORDER BY DT.duracionTotal; 
END; 
$$ LANGUAGE plpgsql; 

------9------------------------------------------
CREATE OR REPLACE FUNCTION calcular_clasificacion_general_por_etapas( 
    id_etapa INT 
) RETURNS TABLE ( 
    ranking INTEGER, 
    primernombre VARCHAR(200), 
    primerapellido VARCHAR(200), 
    tiempoTotal INTERVAL 
) 
AS $$ 
BEGIN 
    RETURN QUERY  
    WITH ClasificacionGeneral AS ( 
        SELECT    
            C.idCiclista,   
            C.primerNombre, 
            C.primerApellido,  
            E.idEdicion,   
            SUM(  
                RE.duracion::INTERVAL   
                + COALESCE(RE.bonificacion::INTERVAL, INTERVAL '0' SECOND)   
                - COALESCE(RE.penalizacion::INTERVAL, INTERVAL '0' SECOND)  
            ) AS tiempoTotal   
        FROM    
            Ciclistas C   
        JOIN    
            RegistroEtapas RE ON C.idCiclista = RE.idCiclista   
        JOIN    
            Etapas E ON RE.idEtapa = E.idEtapa   
        WHERE   
            C.idCiclista NOT IN (  
                SELECT idCiclista  
                FROM Abandonos A  
                JOIN Etapas E2 ON A.idEtapa = E2.idEtapa  
                WHERE E2.idEdicion = E.idEdicion 
				AND E2.idEtapa <= id_etapa 
            )  
            AND C.idCiclista NOT IN (  
                SELECT idCiclista  
                FROM Sanciones S  
                JOIN Etapas E3 ON S.idEtapa = E3.idEtapa  
                WHERE E3.idEdicion = E.idEdicion  
                AND E3.idEtapa <= id_etapa  -- Excluir ciclistas sancionados en etapas posteriores 
            )  
            AND E.idEdicion = (SELECT idEdicion FROM Etapas WHERE idEtapa = id_etapa) -- Solo para la misma edición que la etapa solicitada 
            AND E.idEtapa <= id_etapa 
        GROUP BY    
            C.idCiclista, E.idEdicion   
    ) 
    SELECT  
        CAST(RANK() OVER (ORDER BY cg.tiempoTotal ASC) AS INTEGER) AS ranking, 
        cg.primerNombre, 
        cg.primerApellido, 
        cg.tiempoTotal 
    FROM  
        ClasificacionGeneral cg 
    ORDER BY  
        ranking; 
END; 
$$ LANGUAGE plpgsql; 

--VISTAS-------------------------------------------------------------------------------------------------------------------

------1------------------------------------------
CREATE VIEW CiclistasLideresDeEquipo   
AS   
SELECT DISTINCT c.primerNombre, c.primerApellido 
FROM ciclistas c   
INNER JOIN registroderoles r ON c.idciclista = r.idciclista   
INNER JOIN tipoderoles t ON r.idtiporol = t.idtiporol   
WHERE t.nombre = 'Líder del equipo'; 

------2------------------------------------------
CREATE OR REPLACE VIEW ClasificacionGeneralFinal AS 
SELECT  
    C.idCiclista, 
    COALESCE(C.primerNombre, '') || ' ' || COALESCE(C.segundoNombre, '') || ' ' || COALESCE(C.primerApellido, '') || ' ' || COALESCE(C.segundoApellido, '') AS nombreCiclista, 
    E.idEdicion, 
    SUM(
        RE.duracion::INTERVAL 
        + COALESCE(RE.bonificacion::INTERVAL, INTERVAL '0' SECOND) 
        - COALESCE(RE.penalizacion::INTERVAL, INTERVAL '0' SECOND)
    ) AS tiempoTotal 
FROM  
    Ciclistas C 
JOIN  
    RegistroEtapas RE ON C.idCiclista = RE.idCiclista 
JOIN  
    Etapas E ON RE.idEtapa = E.idEtapa 
WHERE 
    C.idCiclista NOT IN (
        SELECT idCiclista
        FROM Abandonos A
        JOIN Etapas E2 ON A.idEtapa = E2.idEtapa
        WHERE E2.idEdicion = E.idEdicion
    )
    AND C.idCiclista NOT IN (
        SELECT idCiclista
        FROM Sanciones S
        JOIN Etapas E3 ON S.idEtapa = E3.idEtapa
        WHERE E3.idEdicion = E.idEdicion
    )
GROUP BY  
    C.idCiclista, E.idEdicion 
ORDER BY  
    E.idEdicion, tiempoTotal;

------3------------------------------------------
CREATE OR REPLACE VIEW CiclistasMejoresTiemposDeCadaEtapas AS 
SELECT  
    E.idEdicion, 
    E.numeroEtapa, 
    C.idCiclista, 
    COALESCE(C.primerNombre, '') || ' ' || COALESCE(C.segundoNombre, '') || ' ' || COALESCE(C.primerApellido, '') || ' ' || COALESCE(C.segundoApellido, '') AS nombreCiclista, 
    RE.duracion AS tiempoGanador 
FROM  
    Etapas E 
JOIN  
    RegistroEtapas RE ON E.idEtapa = RE.idEtapa 
JOIN  
    Ciclistas C ON RE.idCiclista = C.idCiclista 
WHERE 
    RE.duracion = (
        SELECT MIN(duracion) 
        FROM RegistroEtapas 
        WHERE idEtapa = E.idEtapa
    )
ORDER BY  
    E.idEdicion, E.numeroEtapa;


------4------------------------------------------
CREATE OR REPLACE VIEW CiclistasAbandonados AS
SELECT
    E.idEdicion,
    A.idCiclista,
    CONCAT(C.primerNombre, ' ', C.primerApellido) AS nombreCiclista,
    A.idEtapa,
    A.razonAbandono
FROM
    Abandonos A
JOIN
    Etapas E ON A.idEtapa = E.idEtapa
JOIN
    Ciclistas C ON A.idCiclista = C.idCiclista
ORDER BY
    E.idEdicion, A.idEtapa;


------5------------------------------------------
CREATE OR REPLACE VIEW PenalizacionesEdicion AS
SELECT 
    E.idEdicion,
    E.numeroEtapa,
    C.idCiclista,
    COALESCE(C.primerNombre, '') || ' ' || COALESCE(C.segundoNombre, '') || ' ' || COALESCE(C.primerApellido, '') || ' ' || COALESCE(C.segundoApellido, '') AS nombreCiclista,
    RE.penalizacion AS tiempoPenalizacion
FROM 
    RegistroEtapas RE
JOIN 
    Etapas E ON RE.idEtapa = E.idEtapa
JOIN 
    Ciclistas C ON RE.idCiclista = C.idCiclista
WHERE 
    RE.penalizacion IS NOT NULL AND RE.penalizacion <> '00:00:00'
ORDER BY 
    E.idEdicion, E.numeroEtapa, C.idCiclista;


 
------6------------------------------------------
CREATE OR REPLACE VIEW MaillotsGanados AS 
WITH MaillotPeriodos AS (
    SELECT
        RM.idCiclista,
        C.primerNombre,
        C.segundoNombre,
        C.primerApellido,
        C.segundoApellido,
        M.nombre AS nombreMaillot,
        E.idEdicion,
        E.numeroEtapa,
        LAG(E.numeroEtapa) OVER (PARTITION BY RM.idCiclista, M.nombre, E.idEdicion ORDER BY E.numeroEtapa) AS prevEtapa
    FROM
        RegistroMaillots RM
    JOIN
        Etapas E ON RM.idEtapa = E.idEtapa
    JOIN
        Ciclistas C ON RM.idCiclista = C.idCiclista
    JOIN
        Maillot M ON RM.idMaillot = M.idMaillot
    JOIN
        TipoDeMaillot TDM ON M.idTipoMaillot = TDM.idTipoMaillot
),
GroupedMaillots AS (
    SELECT
        idCiclista,
        primerNombre,
        segundoNombre,
        primerApellido,
        segundoApellido,
        nombreMaillot,
        idEdicion,
        numeroEtapa,
        SUM(CASE WHEN numeroEtapa = prevEtapa + 1 THEN 0 ELSE 1 END) OVER (PARTITION BY idCiclista, nombreMaillot, idEdicion ORDER BY numeroEtapa) AS grp
    FROM
        MaillotPeriodos
)
SELECT
    idEdicion,
    idCiclista,
    COALESCE(primerNombre, '') || ' ' || COALESCE(segundoNombre, '') || ' ' || COALESCE(primerApellido, '') || ' ' || COALESCE(segundoApellido, '') AS nombreCiclista,
    nombreMaillot,
    MIN(numeroEtapa) AS etapaInicio,
    MAX(numeroEtapa) AS etapaFin
FROM
    GroupedMaillots
GROUP BY
    idEdicion, idCiclista, primerNombre, segundoNombre, primerApellido, segundoApellido, nombreMaillot,grp
ORDER BY
    idEdicion, idCiclista, nombreMaillot, etapaInicio;

------7------------------------------------------
CREATE OR REPLACE VIEW CiclistasSancionados AS
SELECT
    E.idEdicion,
    S.idCiclista,
    CONCAT(C.primerNombre, ' ', C.primerApellido) AS nombreCiclista,
    S.idEtapa,
    R.nombre AS reglaViolada
FROM
    Sanciones S
JOIN
    Etapas E ON S.idEtapa = E.idEtapa
JOIN
    Ciclistas C ON S.idCiclista = C.idCiclista
JOIN
    Reglas R ON S.idRegla = R.idRegla
ORDER BY
    E.idEdicion, S.idEtapa;

------8------------------------------------------
CREATE OR REPLACE VIEW CiclistasEquiposEdicion AS
SELECT 
    EE.idEdicion,
    C.idCiclista,
    COALESCE(C.primerNombre, '') || ' ' || COALESCE(C.segundoNombre, '') || ' ' || COALESCE(C.primerApellido, '') || ' ' || COALESCE(C.segundoApellido, '') AS nombreCiclista,
    EQ.nombre AS nombreEquipo
FROM 
    EquiposDeCiclistas EDC
JOIN 
    Ciclistas C ON EDC.idCiclista = C.idCiclista
JOIN 
    Equipos EQ ON EDC.idEquipo = EQ.idEquipo
JOIN 
    Ediciones EE ON EDC.idEdicion = EE.idEdicion
ORDER BY 
    EE.idEdicion, C.idCiclista;

------9------------------------------------------
CREATE OR REPLACE VIEW CiudadesEtapasEdicion AS
SELECT 
    EE.idEdicion,
    E.numeroEtapa,
    CI.nombre AS ciudadInicio,
    CF.nombre AS ciudadFin
FROM 
    Etapas E
JOIN 
    Ediciones EE ON E.idEdicion = EE.idEdicion
JOIN 
    Ciudades CI ON E.idCiudadDeInicio = CI.idCiudad
JOIN 
    Ciudades CF ON E.idCiudadDeFin = CF.idCiudad
ORDER BY 
    EE.idEdicion, E.numeroEtapa;
