/**********************************************************************************
Desarrollado por: Globant
Autor: Braulio Cavieres
Proyecto: Colmena
Descripción: Trigger del objeto Caso
Test: CaseTriggerHandler__test
---------------------------------------------------------------------------------
No.   Fecha       Autor   Descripción
------ ----------  -------------------------------------------------------------- 
1.0   30-12-2019   BC     Creación del Trigger.
***********************************************************************************/

trigger CaseTrigger on Case (before insert,before update,before delete,after insert,after update,after delete,after undelete) {
    {
        if(system.isFuture()) return;
        //nombreClase handler = new nombreClase (Trigger.isExecuting, Trigger.size);
        
        
        
        if ( Trigger.isAfter && Trigger.isInsert) 
        {
           
            CaseTriggerHandler.onAfterInsert(Trigger.new,Trigger.newMap);
        }
        
        else if( Trigger.isAfter && Trigger.isUpdate )
        {
           
            CaseTriggerHandler.onAfterUpdate(Trigger.new,Trigger.newMap);
        }

        else if (  Trigger.isBefore && Trigger.isInsert ) 
        { 
           
            CaseTriggerHandler.onBeforeInsert( Trigger.new,Trigger.newMap);
        }
       
        else if( Trigger.isBefore && Trigger.isUpdate)
        {
           
            CaseTriggerHAndler.onBeforeUpdate(Trigger.new,Trigger.newMap);
        }
    }
}