package com.kiya.bankinggenie.dbu

import android.util.Log
import org.json.JSONArray
import java.io.File

class MenuMatcher(context: android.content.Context, modelsDir: File, private val onnx: OnnxInferenceEngine) {

    companion object {
        private const val TAG = "MenuMatcher"
    }

    data class MenuItem(val menu: String, val keys: List<String>, val subMenus: List<SubMenuItem>)
    data class SubMenuItem(val name: String, val keys: List<String>)

    private val menus: List<MenuItem> = loadMenus(modelsDir)

    private fun loadMenus(modelsDir: File): List<MenuItem> {
        val json = File(modelsDir, "menus.json").readText()
        val arr  = JSONArray(json)
        val list = mutableListOf<MenuItem>()
        for (i in 0 until arr.length()) {
            val obj  = arr.getJSONObject(i)
            val keys = (0 until obj.getJSONArray("keys").length()).map { obj.getJSONArray("keys").getString(it) }
            val subMenus = mutableListOf<SubMenuItem>()
            val subArr   = obj.getJSONArray("subMenus")
            for (j in 0 until subArr.length()) {
                val sub     = subArr.getJSONObject(j)
                val subKeys = (0 until sub.getJSONArray("keys").length()).map { sub.getJSONArray("keys").getString(it) }
                subMenus.add(SubMenuItem(sub.getString("name"), subKeys))
            }
            list.add(MenuItem(obj.getString("menu"), keys, subMenus))
        }
        Log.i(TAG, "✔ Loaded ${list.size} menus from menus.json")
        return list
    }

    fun mainInitializer(query: String): Pair<String?, Float> {
        Log.i(TAG, "--- Main_intializer | query=$query")
        data class CorpusItem(val key: String, val menu: String)
        val corpus = menus.flatMap { m -> m.keys.map { CorpusItem(it, m.menu) } }
        if (corpus.isEmpty()) { Log.w(TAG, "--- Corpus is empty"); return Pair(null, 0f) }

        val queryEmb = onnx.encodeMiniLM(query)
        val scores   = corpus.map { onnx.cosineSimilarity(queryEmb, onnx.encodeMiniLM(it.key)) }
        val top3     = scores.indices.sortedByDescending { scores[it] }.take(3)
        val topScore = scores[top3[0]]

        Log.i(TAG, "--- Top score: $topScore | Top match: ${corpus[top3[0]].menu} | key: ${corpus[top3[0]].key}")
        if (topScore < 0.50f) { Log.w(TAG, "--- Score $topScore < 0.50 → no menu matched"); return Pair(null, topScore) }

        val topMenus = top3.map { corpus[it].menu }.distinct()
        Log.i(TAG, "--- Top menus for reranking: $topMenus")
        val bestMenu = reranker(topMenus, query)
        Log.i(TAG, "--- After reranking: bestMenu=$bestMenu")
        return Pair(bestMenu, topScore)
    }

    fun reranker(candidateMenus: List<String>, query: String): String? {
        Log.i(TAG, "--- Reranker | candidates=$candidateMenus")
        data class Item(val key: String, val menu: String)
        val corpus = candidateMenus.flatMap { menuName ->
            menus.find { it.menu == menuName }?.keys?.map { Item(it, menuName) } ?: emptyList()
        }
        if (corpus.isEmpty()) return candidateMenus.firstOrNull()
        val queryEmb = onnx.encodeMpnet(query)
        val best = corpus.maxByOrNull { onnx.cosineSimilarity(queryEmb, onnx.encodeMpnet(it.key)) }
        Log.i(TAG, "--- Reranker best: menu=${best?.menu}")
        return best?.menu
    }

    fun submenuInitializer(mainMenu: String?, query: String): Pair<String?, Float> {
        Log.i(TAG, "--- Submenu_Initializer | mainMenu=$mainMenu")
        if (mainMenu == null) return Pair(null, 0f)
        val menuItem = menus.find { it.menu == mainMenu } ?: return Pair(null, 0f)
        if (menuItem.subMenus.isEmpty()) { Log.i(TAG, "--- No submenus → returning mainMenu"); return Pair(mainMenu, 1f) }

        data class Item(val key: String, val subMenu: String)
        val corpus = menuItem.subMenus.flatMap { sub -> sub.keys.map { Item(it, sub.name) } }
        if (corpus.isEmpty()) return Pair(mainMenu, 1f)

        val queryEmb = onnx.encodeMiniLM(query)
        val best = corpus.map { Pair(it, onnx.cosineSimilarity(queryEmb, onnx.encodeMiniLM(it.key))) }
            .maxByOrNull { it.second }!!

        Log.i(TAG, "--- Best submenu: ${best.first.subMenu} score=${best.second}")
        return if (best.second > 0.40f) {
            Log.i(TAG, "--- Submenu matched: ${best.first.subMenu}")
            Pair(best.first.subMenu, best.second)
        } else {
            Log.w(TAG, "--- Submenu score ${best.second} < 0.40 → Context not found")
            Pair("Context not found", best.second)
        }
    }

    fun resolveContext(query: String): String? {
        Log.i(TAG, "--- resolveContext | query=$query")
        val (mainMenu, _) = mainInitializer(query)
        val (bestMenu, _) = submenuInitializer(mainMenu, query)
        Log.i(TAG, "--- resolveContext result: $bestMenu")
        return if (bestMenu == "Context not found") null else bestMenu
    }
}
