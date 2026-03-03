({
	doInit : function(component, event, helper) {
		var action = component.get("c.obterContas");
        action.setParams({idConta:"001i000001ditC9AAI"});
        action.setCallback( this, function(response){
            var state = response.getState();
            if(state == "SUCCESS" )
            {
                var accounts = response.getReturnValue();
                console.log("===> Account:" +  JSON.stringify(accounts) );
                
                component.set("v.accounts",accounts);
            }
        } );
        $A.enqueueAction(action);
	}
})