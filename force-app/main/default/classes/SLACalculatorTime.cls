/**********************************************************************************
Desarrollado por: Globant
Autor: Mariano Hernández
Proyecto: Colmena
Descripción: Trigger del objeto Caso
Clase test : SLACalcultatorTime_test
---------------------------------------------------------------------------------
No.   Fecha       Autor   Descripción
------ ----------  -------------------------------------------------------------- 
1.0   14-01-2019   MH     Creación de clase de test.
***********************************************************************************/

global class SLACalculatorTime implements Support.MilestoneTriggerTimeCalculator {   
    global Integer calculateMilestoneTriggerTime(String caseId, String milestoneTypeId){
        //Case c = [SELECT Priority,COL_Categoria__c, COL_Subcategoria__c, COL_Elemento__c FROM Case WHERE Id=:caseId];
        Case c = [SELECT Priority FROM Case WHERE Id =: caseId ];
        
        return CaseTimeGenerator.generateTime(c);
    }
}