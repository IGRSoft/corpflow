# Rollback Plan Template

#### Template — prerequisites, triggers, steps 1–3

~~~markdown
## Rollback Plan: v[X.Y.Z]

### Prerequisites
- [ ] Previous version artifacts available
- [ ] Database rollback scripts tested
- [ ] Feature flags identified

### Trigger Conditions
Initiate rollback if:
- Error rate > [threshold]%
- Latency P99 > [threshold]ms
- Critical functionality broken
- Data integrity issues detected

### Rollback Steps

1. **Notify stakeholders**
   - Inform on-call and team leads
   - Update status page

2. **Stop new deployment**
   - Halt any in-progress rollout
   - Remove from deployment queue

3. **Revert application**
   ```bash
   # Example commands
   kubectl rollout undo deployment/app
   # or
   git revert HEAD && git push
   ```
~~~

#### Template — steps 4–6, data, communication

~~~markdown
<!-- …continued: Rollback Plan steps 4–6 and closing sections -->

4. **Revert database** (if applicable)
   ```sql
   -- Run rollback migration
   -- Verify data integrity
   ```

5. **Verify rollback**
   - Check error rates
   - Verify functionality
   - Monitor for 30 minutes

6. **Post-rollback**
   - Document incident
   - Schedule post-mortem
   - Plan fix for next release

### Data Considerations
- [Describe any data migration impacts]
- [Describe data recovery steps if needed]

### Communication
- [ ] Internal: [channel]
- [ ] External: [status page]
- [ ] Customers: [if applicable]
~~~
