/**********************************************************************************
Desarrollado por: Globant
Autor: Mariano Hernández
Proyecto: Colmena
Descripción:  Generador de tiempos para SLA
Clase de test : CaseTriggerHandler
---------------------------------------------------------------------------------
No.   Fecha       Autor   Descripción
------ ----------  -------------------------------------------------------------- 
1.0   14-01-2019   MH     Creación de clase.
***********************************************************************************/
public class CaseTimeGenerator {
    public static Integer generateTime(Case caso)
	{
        Integer valorDefecto;
        /*
        //Custom Setting COL_SLA__c
		COL_SLA__c slaDef = COL_SLA__c.getInstance('defaultValue'); 
        
		if (slaDef != null && slaDef.COL_minutos__c != null )
		{
            valorDefecto=Integer.ValueOf(slaDef.COL_minutos__c);
        }
        else
		{*/
            //valorDefecto = 7200;
        valorDefecto = 2;
        //}
		/*
        if( ! String.IsBlank(caso.COL_Categoria__c) && ! String.IsBlank(caso.COL_Subcategoria__c))
        {
            //Se toma valor en blanco si no se tiene Elemento
            String slaElemento = !String.isEmpty(c.COL_Elemento__c) ? c.COL_Elemento__c : '';
            //Se concatenan los valores para buscar en la custom setting
            String slaconca;
            
            slaconca = caso.COL_Categoria__c + caso.COL_Subcategoria__c + slaElemento;
            //Se eliminan los espacios
            
            slaconca=slaconca.replaceAll(' ', '');
            
            List<COL_SLA__c>sla = [SELECT COL_Minutos__c FROM COL_SLA__c WHERE COL_NombreSLA__c = :slaconca LIMIT 1];
            //COL_SLA__c sla = COL_SLA__c.getInstance(slaconca);
            //crear metadata para sla nombre y sla(time)
            
            if (!sla.isEmpty() && sla[0].COL_minutos__c != null ){
                return Integer.valueOf(sla[0].COL_minutos__c); 
            }
            else {
                //Valor por defecto 2 dias
                return valorDefecto;
            }                
        }
		else
		{
            //Valor por defecto 2 dias
            */
            return valorDefecto;
        //}
		
    }
}