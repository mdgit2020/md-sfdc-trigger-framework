public class OpportunityTriggerHandler implements ITriggerHandler {
    
	public void beforeInsert(List<SObject> nOpportunityRecords) {
        System.debug('Opportunity Before Insert');
    }
    
    public void beforeUpdate(Map<Id, SObject> nOpportunityRecords, Map<Id, SObject> oOpportunityRecords) {
        System.debug('Opportunity Before Update');
    }
    
    public void beforeDelete(Map<Id, SObject> oOpportunityRecords) {
        System.debug('Opportunity Before Delete');
    }
    
    public void afterInsert(Map<Id, SObject> nOpportunityRecords) {
		System.debug('Opportunity After Insert');
    	Opportunity opportunityRecord = new Opportunity(Name = 'Opportunity-1', StageName = 'Qualification', CloseDate = Date.today() + 1, Amount = 1050000);
        insert opportunityRecord;
    }
    
    public void afterUpdate(Map<Id, SObject> nOpportunityRecords, Map<Id, SObject> oOpportunityRecords) {
		System.debug('Opportunity After Update');
    }
    
    public void afterDelete(Map<Id, SObject> oOpportunityRecords) {
        System.debug('Opportunity After Delete');
    }
    
    public void afterUndelete(Map<Id, SObject> oOpportunityRecords) {
    	System.debug('Opportunity After Undelete');    	
    }	
    
    public boolean seekPermission(TriggerEventRouter.TriggerInfo tInfo) {
        if(!tInfo.possibleRecursion || tInfo.eventName == 'beforeInsert') return true;
        return false;
    }
}