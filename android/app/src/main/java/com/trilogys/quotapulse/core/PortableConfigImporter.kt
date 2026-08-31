package com.trilogys.quotapulse.core

import android.content.Context

data class PortableImportResult(val added:Int,val updated:Int,val credentialsImported:Int)
enum class PortableImportMode { MERGE, REPLACE }

class PortableConfigManager(context:Context) {
    private val accounts=AccountStore(context)
    private val credentials=CredentialStore(context)

    fun export(includeCredentials:Boolean):String = PortableConfigCodec.encode(accounts.accounts(), credentials::get, includeCredentials)

    fun import(raw:String, mode:PortableImportMode=PortableImportMode.MERGE):PortableImportResult {
        val imported=PortableConfigCodec.decode(raw)
        val old=accounts.accounts()
        val result=if(mode==PortableImportMode.REPLACE) mutableListOf() else old.toMutableList()
        if(mode==PortableImportMode.REPLACE) old.forEach { oldAccount ->
            credentials.delete(oldAccount.id)
            accounts.delete(oldAccount.id) // also removes stale snapshot/cooldown data
        }
        var added=0;var updated=0;var credentialCount=0
        imported.forEach { item ->
            val match=result.indexOfFirst { current ->
                current.id==item.record.id || (
                    item.providerAccountId!=null && current.provider==item.record.provider &&
                    (current.providerAccountId==item.providerAccountId || credentials.get(current.id)?.accountId==item.providerAccountId)
                )
            }
            if(match>=0){
                val target=result[match]
                result[match]=item.record.copy(id=target.id, providerAccountId=item.providerAccountId ?: target.providerAccountId, createdAtEpochSeconds=target.createdAtEpochSeconds)
                item.credential?.let{credentials.save(target.id,it);credentialCount++}
                updated++
            } else {
                result+=item.record
                item.credential?.let{credentials.save(item.record.id,it);credentialCount++}
                added++
            }
        }
        accounts.replaceAccounts(result)
        result.forEach{accounts.clearCooldown(it.id)}
        return PortableImportResult(added,updated,credentialCount)
    }
}
