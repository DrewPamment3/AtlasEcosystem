AtlasPropertyConfig = {}

-- Distance & Timing Constants
AtlasPropertyConfig.NearbyScanRadius = 50.0       -- meters: only track properties within this range
AtlasPropertyConfig.NearbyScanInterval = 5000     -- ms (5 seconds): how often to refresh nearby list
AtlasPropertyConfig.BoundaryCheckInterval = 500   -- ms (0.5 seconds): how often to check if player is inside a boundary

-- Property Types (used in admin menu for selection/validation)
AtlasPropertyConfig.PropertyTypes = {
    "house",
    "business",
    "farm",
    "public",
    "business_npc",
    "warehouse"
}

-- Admin Groups allowed to manage properties
AtlasPropertyConfig.AdminGroups = {
    "admin",
    "superadmin"
}

-- Debug Logging
AtlasPropertyConfig.DebugLogging = false

-- ============================================================
-- BOUNDARY GEOMETRY: POINT-IN-QUADRILATERAL TEST
-- ============================================================
-- Uses ray-casting algorithm.
-- Casts a horizontal ray from the test point (px, py) to the right
-- and counts how many polygon edges it intersects.
--    Odd  = point is INSIDE
--    Even = point is OUTSIDE

---@param px number Test point X
---@param py number Test point Y
---@param polygon table Array of {x, y, z} tables (expects exactly 4)
---@return boolean true if point is inside the quadrilateral
function AtlasPropertyConfig.IsPointInQuadrilateral(px, py, polygon)
    if not polygon or #polygon < 4 then
        return false
    end

    local inside = false
    local n = #polygon

    for i = 1, n do
        local j = (i % n) + 1

        local xi, yi = polygon[i].x, polygon[i].y
        local xj, yj = polygon[j].x, polygon[j].y

        -- Check if edge crosses the horizontal ray at py
        if ((yi > py) ~= (yj > py)) then
            local intersectX = (xj - xi) * (py - yi) / (yj - yi) + xi
            if px < intersectX then
                inside = not inside
            end
        end
    end

    return inside
end

-- ============================================================
-- CENTROID CALCULATION
-- ============================================================
-- Used to find the center of a property for proximity checks.
-- Averages all 4 boundary points (x and y only).

---@param polygon table Array of {x, y, z} tables
---@return number centroidX
---@return number centroidY
function AtlasPropertyConfig.GetCentroid(polygon)
    if not polygon or #polygon == 0 then
        return 0.0, 0.0
    end

    local sumX, sumY = 0.0, 0.0
    for _, point in ipairs(polygon) do
        sumX = sumX + (point.x or 0.0)
        sumY = sumY + (point.y or 0.0)
    end

    return sumX / #polygon, sumY / #polygon
end
